-- Phase 7: self-service account deletion.
--
-- SAFETY (additive + data-safe on existing rows):
--   * No table is dropped, no existing row is deleted or modified by the
--     migration itself.
--   * `users` and `parking_listings` gain a `deleted_at` soft-delete column so
--     account deletion can keep referencing rows (bookings, payments,
--     conversations) valid while scrubbing the personally identifiable data.
--   * `bookings.vehicle_id` becomes nullable and its FK switches to
--     ON DELETE SET NULL, so deleting a vehicle user's vehicles does NOT
--     cascade into their booking history — the bookings stay, with the
--     vehicle reference cleared.
--   * Partial indexes keep the "which accounts / listings are currently live"
--     lookups fast now that deleted rows stay in place.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE parking_listings
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Booking history must survive vehicle deletion: NULL the vehicle reference
-- instead of cascading the deletion into the bookings row.
ALTER TABLE bookings
    DROP CONSTRAINT IF EXISTS bookings_vehicle_id_fkey;

ALTER TABLE bookings
    ALTER COLUMN vehicle_id DROP NOT NULL;

ALTER TABLE bookings
    ADD CONSTRAINT bookings_vehicle_id_fkey
    FOREIGN KEY (vehicle_id) REFERENCES vehicles(id)
    ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_users_active
    ON users(id)
    WHERE is_active = TRUE AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_parking_listings_active
    ON parking_listings(id)
    WHERE deleted_at IS NULL;