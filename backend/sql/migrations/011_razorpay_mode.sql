-- Phase 11: persist the Razorpay mode on every online payment.
--
-- WHY THIS EXISTS
-- ---------------
-- Test-mode and live-mode Razorpay payments both look like `SUCCESS` in the
-- existing schema. That is enough to create an owner earning, but it must NOT
-- be enough to pay the owner out: a test-mode payment is audit evidence only.
-- This migration records the mode that created each order, so manual
-- settlement can refuse anything that was not created with live keys.
--
-- SAFETY
--   * Additive only: no table, row or money field is deleted.
--   * The only data write is the one-time backfill below. It does not change a
--     booking, payment status, amount or earning; it only labels the order.
--   * No Razorpay API call, no Route activation, no linked account, no transfer.
--   * Migrations 001-010 are not edited.
--   * Every statement is idempotent where PostgreSQL allows it.
--
-- LEGACY ROWS
-- -----------
-- Payments created before this migration have no recorded mode. The audited
-- deployment used only `rzp_test_...` keys, so existing Razorpay rows are
-- labelled `test`. That is deliberately fail-closed: if this migration is ever
-- applied to a different database with older live rows, those rows must be
-- reconciled and explicitly set to `live` by an operator before settlement.
-- Null or unknown values are always treated as non-settleable.

ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS razorpay_mode TEXT;

-- One-time metadata backfill for the existing test-mode deployment.
UPDATE payments
SET razorpay_mode = 'test'
WHERE payment_method = 'RAZORPAY'
  AND razorpay_mode IS NULL;

ALTER TABLE payments
    DROP CONSTRAINT IF EXISTS payments_razorpay_mode_check;

ALTER TABLE payments
    ADD CONSTRAINT payments_razorpay_mode_check
    CHECK (razorpay_mode IS NULL OR razorpay_mode IN ('test', 'live'));

CREATE INDEX IF NOT EXISTS idx_payments_razorpay_mode
    ON payments(razorpay_mode);

COMMENT ON COLUMN payments.razorpay_mode IS
    'Razorpay key mode that created this order: test or live. NULL means legacy/unknown and is never settleable.';
