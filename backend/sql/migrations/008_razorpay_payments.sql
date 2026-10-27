-- Phase 8: Razorpay online payments (safe, additive).
--
-- SAFETY:
--   * No DROP TABLE, no DELETE, no TRUNCATE.
--   * No existing user / parking / booking / payment row is destroyed or
--     rewritten by this migration.
--   * Migrations 001-007 are NOT edited.
--   * Every statement is idempotent where PostgreSQL allows it.
--
-- DESIGN NOTES (adjusted to the EXISTING schema):
--   * `payments.amount` / `bookings.amount` stay DOUBLE PRECISION rupees for
--     backward compatibility. Razorpay amounts are stored in the new
--     `payments.amount_paise` BIGINT column so gateway math is integer-only.
--   * The authoritative paid state reuses the existing `SUCCESS` value, which
--     is already in `PaymentStatus.paid` and therefore already counted in owner
--     earnings. The richer Razorpay lifecycle lives in the new
--     `verification_status` / `razorpay_status` columns instead of inventing a
--     competing earnings path.
--   * 'CREATED' is added to the payment-status allow-lists for the moment
--     between "Razorpay order exists" and "payment confirmed".
--   * 'RAZORPAY' is added to the payment-method allow-lists.

-- ============================================================
-- 1. PAYMENT METHODS: allow RAZORPAY in addition to UPI / COD
-- ============================================================

ALTER TABLE payments
    DROP CONSTRAINT IF EXISTS payments_payment_method_check;

ALTER TABLE payments
    ADD CONSTRAINT payments_payment_method_check
    CHECK (payment_method IN ('UPI', 'COD', 'RAZORPAY'));

ALTER TABLE bookings
    DROP CONSTRAINT IF EXISTS bookings_payment_method_check;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_payment_method_check
    CHECK (
        payment_method IS NULL
        OR payment_method IN ('UPI', 'COD', 'RAZORPAY')
    );

-- ============================================================
-- 2. PAYMENT STATUS: allow CREATED (order exists, not yet paid)
-- ============================================================

ALTER TABLE payments
    DROP CONSTRAINT IF EXISTS payments_payment_status_check;

ALTER TABLE payments
    ADD CONSTRAINT payments_payment_status_check
    CHECK (
        payment_status IN (
            'CREATED',
            'PENDING',
            'UPI_PENDING_VERIFICATION',
            'SUCCESS',
            'FAILED',
            'REFUNDED',
            'COD_PENDING',
            'COD_CONFIRMED'
        )
    );

ALTER TABLE bookings
    DROP CONSTRAINT IF EXISTS bookings_payment_status_check;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_payment_status_check
    CHECK (
        payment_status IS NULL
        OR payment_status IN (
            'CREATED',
            'PENDING',
            'UPI_PENDING_VERIFICATION',
            'SUCCESS',
            'FAILED',
            'REFUNDED',
            'COD_PENDING',
            'COD_CONFIRMED'
        )
    );

-- ============================================================
-- 3. PAYMENTS: Razorpay + integer-money columns
-- ============================================================

ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS provider TEXT,
    ADD COLUMN IF NOT EXISTS currency TEXT NOT NULL DEFAULT 'INR',
    ADD COLUMN IF NOT EXISTS amount_paise BIGINT,
    ADD COLUMN IF NOT EXISTS razorpay_order_id TEXT,
    ADD COLUMN IF NOT EXISTS razorpay_payment_id TEXT,
    ADD COLUMN IF NOT EXISTS razorpay_signature TEXT,
    ADD COLUMN IF NOT EXISTS razorpay_status TEXT,
    ADD COLUMN IF NOT EXISTS verification_status TEXT;

-- One Razorpay order id and one Razorpay payment id may each appear at most
-- once, so a duplicate webhook or callback can never create a second payment.
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_razorpay_order
    ON payments(razorpay_order_id)
    WHERE razorpay_order_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_razorpay_payment
    ON payments(razorpay_payment_id)
    WHERE razorpay_payment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payments_provider
    ON payments(provider);

-- ============================================================
-- 4. OWNER PAYMENT ACCOUNTS (Razorpay Route linked accounts)
-- ============================================================
--
-- Kept separate from `users` so Route onboarding stays opt-in and no existing
-- row changes. `razorpay_settlement_enabled` defaults FALSE: Route is NOT
-- assumed to be enabled just because the Payment Gateway is.

CREATE TABLE IF NOT EXISTS owner_payment_accounts (
    owner_id                   UUID PRIMARY KEY
                               REFERENCES users(id) ON DELETE CASCADE,
    razorpay_linked_account_id TEXT UNIQUE,
    razorpay_onboarding_status TEXT,
    razorpay_settlement_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- 5. PAYMENT TRANSFERS / OWNER EARNINGS LEDGER
-- ============================================================
--
-- ONE row per payment (`UNIQUE (payment_id)`), so owner earnings and any
-- future Route transfer are idempotent by construction. With Route disabled,
-- `razorpay_transfer_id` stays NULL and `settlement_status` stays 'PENDING'.

CREATE TABLE IF NOT EXISTS payment_transfers (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id                UUID NOT NULL
                              REFERENCES payments(id) ON DELETE CASCADE,
    booking_id                UUID REFERENCES bookings(id) ON DELETE SET NULL,
    owner_id                  UUID NOT NULL
                              REFERENCES users(id) ON DELETE CASCADE,
    razorpay_transfer_id      TEXT UNIQUE,
    razorpay_linked_account_id TEXT,
    gross_amount_paise        BIGINT NOT NULL,
    platform_fee_paise        BIGINT NOT NULL DEFAULT 0,
    owner_amount_paise        BIGINT NOT NULL,
    currency                  TEXT NOT NULL DEFAULT 'INR',
    transfer_status           TEXT NOT NULL DEFAULT 'PENDING',
    settlement_status         TEXT NOT NULL DEFAULT 'PENDING',
    failure_reason            TEXT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (payment_id)
);

CREATE INDEX IF NOT EXISTS idx_payment_transfers_owner
    ON payment_transfers(owner_id);

CREATE INDEX IF NOT EXISTS idx_payment_transfers_settlement
    ON payment_transfers(settlement_status);

-- ============================================================
-- 6. RAZORPAY WEBHOOK EVENT LOG (idempotency)
-- ============================================================

CREATE TABLE IF NOT EXISTS razorpay_webhook_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_key           TEXT NOT NULL UNIQUE,
    event_type          TEXT NOT NULL,
    razorpay_order_id   TEXT,
    razorpay_payment_id TEXT,
    payload             JSONB,
    processed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_razorpay_webhook_order
    ON razorpay_webhook_events(razorpay_order_id);
