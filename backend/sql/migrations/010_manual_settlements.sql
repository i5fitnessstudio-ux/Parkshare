-- Phase 10: Manual (out-of-band) owner settlement.
--
-- CONTEXT:
--   * Customer payments keep going through the standard Razorpay Payment
--     Gateway (unchanged).
--   * Razorpay Route is NOT activated, so ParkShare cannot move an owner's
--     share to them through Razorpay.
--   * Until Route is live, an administrator pays the owner OUTSIDE Razorpay
--     and records that payout against the owner's existing earning row.
--
-- SAFETY:
--   * Additive only: no DROP TABLE, no DELETE, no TRUNCATE.
--   * No existing user / payment / booking / payment_transfers row is
--     destroyed or rewritten by this migration.
--   * Migrations 001-009 are NOT edited.
--   * Every statement is idempotent where PostgreSQL allows it.
--
-- WHAT THIS DOES **NOT** DO:
--   * It does NOT enable Razorpay Route.
--   * It does NOT create a linked account.
--   * It does NOT make any Razorpay transfer API call.
--   * Manual settlement keeps the Razorpay-specific transfer columns NULL;
--     `razorpay_transfer_id` is never written for a manual payout.

-- ============================================================
-- 1. USERS: allow an 'admin' role
-- ============================================================
--
-- Only ever used for back-office settlement operations. The public
-- registration endpoint still refuses to create an admin (UserRole.all in
-- code intentionally excludes it); an operator promotes/creates admins
-- out-of-band.

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;

ALTER TABLE users
    ADD CONSTRAINT users_role_check
    CHECK (role IN ('user', 'owner', 'admin'));

-- ============================================================
-- 2. PAYMENT TRANSFERS: manual-payout audit columns
-- ============================================================
--
-- These describe a payout ParkShare made OUTSIDE Razorpay. They are written
-- only by the admin settlement action and are never populated for a Route
-- transfer (which would instead use `razorpay_transfer_id`).

ALTER TABLE payment_transfers
    ADD COLUMN IF NOT EXISTS manual_payout_reference TEXT,
    ADD COLUMN IF NOT EXISTS manual_payout_note TEXT,
    ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS settled_by_admin_user_id UUID
        REFERENCES users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_payment_transfers_settled_at
    ON payment_transfers(settled_at);
