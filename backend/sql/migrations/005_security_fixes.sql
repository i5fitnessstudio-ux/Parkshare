-- Phase: security hardening (audit C-01, H-05, L-10).
--
-- SAFETY (this migration is strictly additive and data-safe):
--   * No DROP TABLE, no DELETE, no TRUNCATE.
--   * No existing user / parking / booking / payment row is modified.
--   * Existing migrations 001-004 are NOT edited.
--   * Every statement is idempotent, so re-running is safe.
--
-- WHAT IT DOES
-- 1. Adds the `UPI_PENDING_VERIFICATION` payment status to the two CHECK
--    constraints. A UPI payment the payer *claims* is now recorded in an
--    explicit "not verified" state instead of being written straight to
--    SUCCESS with an invented transaction id.
-- 2. Adds the settlement audit columns used when a parking owner verifies a
--    UPI payment (the only path from UPI_PENDING_VERIFICATION to SUCCESS).
-- 3. Adds the OTP brute-force bookkeeping (attempts + last_sent_at) and the
--    indexes the lookup path needs.
-- 4. Adds a partial index for "UPI payments awaiting settlement" so the
--    owner's verification queue stays fast.


-- ============================================================
-- 1. PAYMENT STATUS: add the unverified UPI state
-- ============================================================
--
-- 'UPI_PENDING_VERIFICATION' means: the payer declared the UPI app showed
-- success, but the backend has no verifiable evidence of settlement. It is
-- NOT an earning and it does NOT occupy a slot.

ALTER TABLE bookings
    DROP CONSTRAINT IF EXISTS bookings_payment_status_check;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_payment_status_check
    CHECK (
        payment_status IS NULL
        OR payment_status IN (
            'PENDING',
            'UPI_PENDING_VERIFICATION',
            'SUCCESS',
            'FAILED',
            'REFUNDED',
            'COD_PENDING',
            'COD_CONFIRMED'
        )
    );


ALTER TABLE payments
    DROP CONSTRAINT IF EXISTS payments_payment_status_check;

ALTER TABLE payments
    ADD CONSTRAINT payments_payment_status_check
    CHECK (
        payment_status IN (
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
-- 2. UPI SETTLEMENT AUDIT TRAIL
-- ============================================================
--
-- `verified_*` is written ONLY by owner settlement
-- (PUT /api/payments/{bookingId}/upi/settle) or by a future PSP webhook.

ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS verified_by UUID
        REFERENCES users(id)
        ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS settled_reference TEXT;


ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS upi_verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS upi_verified_by UUID
        REFERENCES users(id)
        ON DELETE SET NULL;


-- ============================================================
-- 3. OTP BRUTE-FORCE BOOKKEEPING
-- ============================================================

ALTER TABLE password_reset_otps
    ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_sent_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS request_ip TEXT;

-- The verification lookup is `WHERE user_id = @uid AND otp_hash = @hash`;
-- without this index it degrades to a sequential scan on a public endpoint.
CREATE INDEX IF NOT EXISTS idx_password_reset_otps_hash
    ON password_reset_otps(otp_hash);

-- Supports the resend cooldown check (most recent OTP per user).
CREATE INDEX IF NOT EXISTS idx_password_reset_otps_user_recent
    ON password_reset_otps(user_id, created_at DESC);


-- ============================================================
-- 4. OWNER SETTLEMENT QUEUE
-- ============================================================
--
-- Partial index: only the rows an owner can act on are indexed, so the index
-- stays tiny while the owner's "verify UPI payment" list is O(log n).

CREATE INDEX IF NOT EXISTS idx_payments_upi_awaiting_verification
    ON payments(booking_id, created_at DESC)
    WHERE payment_method = 'UPI'
      AND payment_status = 'UPI_PENDING_VERIFICATION';


-- ============================================================
-- 5. REFRESH TOKEN HYGIENE
-- ============================================================
--
-- Logout / password-reset revoke in bulk; this index keeps that from
-- degrading into a scan of every token ever issued for that user.

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_active
    ON refresh_tokens(user_id)
    WHERE revoked_at IS NULL;
