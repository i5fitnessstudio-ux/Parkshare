-- Phase 6: per-owner UPI payments + Cash on Delivery (COD).
--
-- SAFETY:
-- - No DROP TABLE
-- - No DELETE
-- - Existing users / parkings / bookings / payments are preserved
-- - Schema changes are additive/idempotent where possible
--
-- Rules:
-- - UPI success -> payment SUCCESS -> booking CONFIRMED
-- - COD selected -> COD_PENDING
-- - COD_PENDING does NOT block a parking slot
-- - Only owner-confirmed COD becomes CONFIRMED and affects earnings/availability


-- ============================================================
-- 1. USERS: UPI ID
-- ============================================================

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS upi_id TEXT;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_upi_id_format;

ALTER TABLE users
    ADD CONSTRAINT users_upi_id_format
    CHECK (
        upi_id IS NULL
        OR upi_id ~ '^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9._-]{2,64}$'
    );


-- ============================================================
-- 2. PAYMENTS: ADD REQUIRED COLUMNS FIRST
--
-- IMPORTANT:
-- These columns MUST exist before we backfill bookings from
-- the payments table.
-- ============================================================

ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS upi_id TEXT,
    ADD COLUMN IF NOT EXISTS reference TEXT,
    ADD COLUMN IF NOT EXISTS raw_response JSONB,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Ensure these exist if older schema did not contain them.
ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS payment_method TEXT,
    ADD COLUMN IF NOT EXISTS payment_status TEXT;

-- COD may not have a gateway transaction id until cash is confirmed.
ALTER TABLE payments
    ALTER COLUMN transaction_id DROP NOT NULL;


-- ============================================================
-- 3. BOOKINGS: PAYMENT / COD COLUMNS
-- ============================================================

ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS payment_method TEXT,
    ADD COLUMN IF NOT EXISTS payment_status TEXT,
    ADD COLUMN IF NOT EXISTS owner_upi_id_snapshot TEXT,
    ADD COLUMN IF NOT EXISTS payment_reference TEXT,
    ADD COLUMN IF NOT EXISTS upi_transaction_id TEXT,
    ADD COLUMN IF NOT EXISTS cod_confirmed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS cod_confirmed_by UUID
        REFERENCES users(id)
        ON DELETE SET NULL;


-- ============================================================
-- 4. BACKFILL BOOKINGS FROM MOST RECENT PAYMENT
-- ============================================================

WITH latest_payment AS (
    SELECT DISTINCT ON (booking_id)
        booking_id,
        payment_method,
        payment_status,
        transaction_id,
        reference,
        upi_id
    FROM payments
    WHERE booking_id IS NOT NULL
    ORDER BY booking_id, created_at DESC
)
UPDATE bookings b
SET
    payment_method = lp.payment_method,
    payment_status = lp.payment_status,
    upi_transaction_id = lp.transaction_id,
    payment_reference = lp.reference,
    owner_upi_id_snapshot = COALESCE(
        b.owner_upi_id_snapshot,
        lp.upi_id
    )
FROM latest_payment lp
WHERE
    lp.booking_id = b.id
    AND b.payment_method IS NULL;


-- ============================================================
-- 5. DEFAULT OLD BOOKINGS
-- ============================================================

-- Old bookings without a payment row become pending UPI.
UPDATE bookings
SET payment_method = 'UPI'
WHERE payment_method IS NULL;

UPDATE bookings
SET payment_status = 'PENDING'
WHERE payment_status IS NULL;


-- ============================================================
-- 6. NORMALISE LEGACY BOOKING PAYMENT METHODS
-- ============================================================

-- Remove legacy CARD / WALLET / NETBANKING values.
UPDATE bookings
SET payment_method = 'UPI'
WHERE payment_method NOT IN ('UPI', 'COD');


ALTER TABLE bookings
    DROP CONSTRAINT IF EXISTS bookings_payment_method_check;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_payment_method_check
    CHECK (
        payment_method IS NULL
        OR payment_method IN ('UPI', 'COD')
    );


ALTER TABLE bookings
    DROP CONSTRAINT IF EXISTS bookings_payment_status_check;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_payment_status_check
    CHECK (
        payment_status IS NULL
        OR payment_status IN (
            'PENDING',
            'SUCCESS',
            'FAILED',
            'REFUNDED',
            'COD_PENDING',
            'COD_CONFIRMED'
        )
    );


-- ============================================================
-- 7. BOOKING STATUS
-- ============================================================

ALTER TABLE bookings
    DROP CONSTRAINT IF EXISTS bookings_status_check;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_status_check
    CHECK (
        status IN (
            'REQUESTED',
            'ACCEPTED',
            'REJECTED',
            'PAYMENT_PENDING',
            'COD_PENDING',
            'CONFIRMED',
            'ACTIVE',
            'COMPLETED',
            'CANCELLED'
        )
    );


CREATE INDEX IF NOT EXISTS idx_bookings_payment_status
    ON bookings(payment_status);

CREATE INDEX IF NOT EXISTS idx_bookings_payment_method
    ON bookings(payment_method);


-- ============================================================
-- 8. NORMALISE PAYMENTS
-- ============================================================

UPDATE payments
SET payment_method = 'UPI'
WHERE
    payment_method IS NULL
    OR payment_method NOT IN ('UPI', 'COD');


UPDATE payments
SET payment_status = 'PENDING'
WHERE payment_status IS NULL;


ALTER TABLE payments
    DROP CONSTRAINT IF EXISTS payments_payment_method_check;

ALTER TABLE payments
    ADD CONSTRAINT payments_payment_method_check
    CHECK (
        payment_method IN ('UPI', 'COD')
    );


ALTER TABLE payments
    DROP CONSTRAINT IF EXISTS payments_payment_status_check;

ALTER TABLE payments
    ADD CONSTRAINT payments_payment_status_check
    CHECK (
        payment_status IN (
            'PENDING',
            'SUCCESS',
            'FAILED',
            'REFUNDED',
            'COD_PENDING',
            'COD_CONFIRMED'
        )
    );


CREATE INDEX IF NOT EXISTS idx_payments_status
    ON payments(payment_status);

CREATE INDEX IF NOT EXISTS idx_payments_method
    ON payments(payment_method);


-- ============================================================
-- 9. OWNER UPI SNAPSHOT ON OLD PAYMENTS
-- ============================================================

UPDATE payments p
SET upi_id = u.upi_id
FROM users u
WHERE
    p.owner_id = u.id
    AND p.upi_id IS NULL
    AND u.upi_id IS NOT NULL;


-- ============================================================
-- 10. COPY OWNER UPI SNAPSHOT INTO BOOKINGS
-- ============================================================

UPDATE bookings b
SET owner_upi_id_snapshot = u.upi_id
FROM parking_listings p
JOIN users u
    ON u.id = p.owner_id
WHERE
    b.parking_id = p.id
    AND b.owner_upi_id_snapshot IS NULL
    AND u.upi_id IS NOT NULL;


-- ============================================================
-- 11. SLOT OCCUPANCY
--
-- COD_PENDING is deliberately excluded.
--
-- Therefore:
--
-- UPI confirmed:
--     CONFIRMED -> blocks space
--
-- COD selected:
--     COD_PENDING -> does NOT block space
--
-- Owner confirms cash:
--     CONFIRMED -> starts blocking space
-- ============================================================

ALTER TABLE bookings
    DROP CONSTRAINT IF EXISTS bookings_no_overlap_per_space;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_no_overlap_per_space
    EXCLUDE USING gist (
        parking_space_id WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    )
    WHERE (
        parking_space_id IS NOT NULL
        AND status IN (
            'ACCEPTED',
            'PAYMENT_PENDING',
            'CONFIRMED',
            'ACTIVE'
        )
    );


DROP INDEX IF EXISTS idx_bookings_space_window;

CREATE INDEX idx_bookings_space_window
    ON bookings(
        parking_space_id,
        start_date,
        end_date
    )
    WHERE status IN (
        'ACCEPTED',
        'PAYMENT_PENDING',
        'CONFIRMED',
        'ACTIVE'
    );