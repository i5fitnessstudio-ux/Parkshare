-- Phase 12: keep the owner payout destination needed for manual settlement.
--
-- CONTEXT
-- -------
-- Razorpay Route is not available for this business. Razorpay's documented
-- fallback is a two-step flow: collect the customer payment normally, then pay
-- the owner out-of-band. A bank payout needs the full account number and IFSC,
-- not just the last four digits.
--
-- Migration 009 deliberately discarded those values because Route onboarding
-- was expected to forward them to Razorpay. With Route unavailable, doing that
-- made manual settlement impossible: an administrator had an amount and an
-- owner, but no destination.
--
-- WHAT THIS ADDS
-- --------------
-- Two ciphertext columns (AES-256-GCM, see PayoutDetailsCipher) plus a
-- timestamp. Existing rows keep only their last-4 metadata; those owners must
-- re-submit the setup before a manual bank payout. No value is guessed.
--
-- SAFETY
-- ------
--   * Additive only: no DROP TABLE, no DELETE, no TRUNCATE, no row rewrite.
--   * Migrations 001-011 are not edited.
--   * No Razorpay API call, no Route activation, no transfer, no linked account.
--   * The columns are nullable so an existing setup remains readable.

ALTER TABLE owner_payment_accounts
    ADD COLUMN IF NOT EXISTS payout_account_number_encrypted TEXT,
    ADD COLUMN IF NOT EXISTS payout_ifsc_encrypted TEXT,
    ADD COLUMN IF NOT EXISTS payout_details_updated_at TIMESTAMPTZ;

-- Only rows with both ciphertext values can feed a manual bank payout. The
-- partial index keeps the back-office "payout-ready owners" lookup cheap.
CREATE INDEX IF NOT EXISTS idx_owner_payment_accounts_payout_ready
    ON owner_payment_accounts(owner_id)
    WHERE payout_account_number_encrypted IS NOT NULL
      AND payout_ifsc_encrypted IS NOT NULL;
