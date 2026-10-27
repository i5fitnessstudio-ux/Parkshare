-- Per-vehicle rental plans: car/bike x monthly/yearly, priced independently.
--
-- Before this migration a listing had ONE monthly and ONE yearly plan shared
-- by every vehicle type. Owners can now enable/disable and price each of the
-- four plans on its own (e.g. cars monthly only, bikes yearly only).
--
-- SAFETY:
-- - No DROP TABLE / No DELETE
-- - Purely additive: new columns, one boolean flag, one backfill UPDATE
-- - Existing listings keep exactly the plans they had: each new column is
--   seeded from the legacy monthly/yearly pair, so a listing that offered
--   monthly rentals still offers them for BOTH cars and bikes.
--
-- Readers fall back to the legacy pair whenever per_vehicle_plans is FALSE
-- (a row written by an old client), so old and new rows behave identically
-- until the owner re-saves them.

-- ============================================================
-- 1. NEW COLUMNS
-- ============================================================

ALTER TABLE parking_listings
    ADD COLUMN IF NOT EXISTS car_monthly_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS car_monthly_rent DOUBLE PRECISION
        CHECK (car_monthly_rent IS NULL OR car_monthly_rent > 0),
    ADD COLUMN IF NOT EXISTS car_yearly_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS car_yearly_rent DOUBLE PRECISION
        CHECK (car_yearly_rent IS NULL OR car_yearly_rent > 0),
    ADD COLUMN IF NOT EXISTS bike_monthly_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS bike_monthly_rent DOUBLE PRECISION
        CHECK (bike_monthly_rent IS NULL OR bike_monthly_rent > 0),
    ADD COLUMN IF NOT EXISTS bike_yearly_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS bike_yearly_rent DOUBLE PRECISION
        CHECK (bike_yearly_rent IS NULL OR bike_yearly_rent > 0),
    ADD COLUMN IF NOT EXISTS per_vehicle_plans BOOLEAN NOT NULL DEFAULT FALSE;

-- ============================================================
-- 2. BACKFILL: existing listings inherit their legacy plans for both types
-- ============================================================

UPDATE parking_listings
SET car_monthly_enabled  = monthly_enabled,
    car_monthly_rent     = monthly_rent,
    car_yearly_enabled   = yearly_enabled,
    car_yearly_rent      = yearly_rent,
    bike_monthly_enabled = monthly_enabled,
    bike_monthly_rent    = monthly_rent,
    bike_yearly_enabled  = yearly_enabled,
    bike_yearly_rent     = yearly_rent,
    per_vehicle_plans    = TRUE
WHERE per_vehicle_plans = FALSE;
