-- Phase 9: Owner payment & settlement account setup (safe, additive).
--
-- SAFETY:
--   * No DROP TABLE, no DELETE, no TRUNCATE, no data rewrite.
--   * Migrations 001-008 are NOT edited.
--   * Every statement is idempotent (ADD COLUMN IF NOT EXISTS).
--
-- CONTEXT:
--   `owner_payment_accounts` was created in 008 as the placeholder for Razorpay
--   Route linked accounts, but nothing ever wrote to it. This migration adds the
--   columns the owner-facing "Payments & Settlements" setup needs.
--
-- PRIVACY:
--   Only `bank_last4` is stored — never the full account number or IFSC. Full
--   bank details are validated in-process and, when Route onboarding is enabled
--   later, forwarded to the provider; they are not persisted here.

ALTER TABLE owner_payment_accounts
    ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'RAZORPAY',
    ADD COLUMN IF NOT EXISTS legal_name TEXT,
    ADD COLUMN IF NOT EXISTS account_type TEXT,
    ADD COLUMN IF NOT EXISTS account_holder_name TEXT,
    ADD COLUMN IF NOT EXISTS bank_last4 TEXT,
    ADD COLUMN IF NOT EXISTS contact_mobile TEXT,
    ADD COLUMN IF NOT EXISTS contact_email TEXT,
    ADD COLUMN IF NOT EXISTS consent_accepted_at TIMESTAMPTZ;

-- `razorpay_onboarding_status` already exists (TEXT, no CHECK) and is reused as
-- the onboarding state: NOT_STARTED / PENDING / VERIFIED / ACTION_REQUIRED /
-- REJECTED. It stays free-text on purpose so a provider-side state can be
-- recorded verbatim without a migration.
