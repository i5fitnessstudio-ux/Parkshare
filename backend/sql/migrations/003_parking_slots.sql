-- Phase 5: slot-based parking capacity.
-- Adds per-parking capacity (maximum_cars / maximum_bikes / allow_mixed_parking),
-- a `parking_spaces` table for the individual physical parking slots, and a
-- nullable `bookings.parking_space_id` so every NEW booking is allocated one
-- specific slot instead of occupying the whole property.
--
-- SAFETY: purely additive. No DROP, no DELETE of users/parkings/bookings/
-- messages. Existing listings are backfilled with one slot each so they stay
-- valid and bookable. Legacy bookings keep parking_space_id = NULL and are
-- treated conservatively (they still hold the whole property for overlapping
-- dates, exactly like before this migration).

-- ============================================================
-- 1. Capacity columns on parking_listings
-- ============================================================
ALTER TABLE parking_listings
    ADD COLUMN IF NOT EXISTS maximum_cars INTEGER,
    ADD COLUMN IF NOT EXISTS maximum_bikes INTEGER,
    ADD COLUMN IF NOT EXISTS allow_mixed_parking BOOLEAN NOT NULL DEFAULT FALSE;

-- ============================================================
-- 2. Individual physical parking slots
-- ============================================================
CREATE TABLE IF NOT EXISTS parking_spaces (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parking_id    UUID NOT NULL REFERENCES parking_listings(id) ON DELETE CASCADE,
    space_code    TEXT NOT NULL,
    space_name    TEXT,
    vehicle_type  TEXT NOT NULL CHECK (vehicle_type IN ('BIKE', 'CAR')),
    length_m      DOUBLE PRECISION NOT NULL CHECK (length_m > 0),
    width_m       DOUBLE PRECISION NOT NULL CHECK (width_m > 0),
    height_m      DOUBLE PRECISION NOT NULL CHECK (height_m > 0),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (parking_id, space_code)
);

CREATE INDEX IF NOT EXISTS idx_parking_spaces_parking
    ON parking_spaces(parking_id, vehicle_type);
CREATE INDEX IF NOT EXISTS idx_parking_spaces_active
    ON parking_spaces(parking_id) WHERE is_active;

-- Backfill: one slot per existing listing, sized with the listing's own
-- dimensions so the pre-existing fit check keeps behaving identically.
-- A BOTH listing gets one car slot and one bike slot.
INSERT INTO parking_spaces
    (parking_id, space_code, space_name, vehicle_type, length_m, width_m, height_m)
SELECT p.id, 'C1', 'Car Space 1', 'CAR', p.length_m, p.width_m, p.height_m
FROM parking_listings p
WHERE p.vehicle_type IN ('CAR', 'BOTH')
  AND NOT EXISTS (
      SELECT 1 FROM parking_spaces s
      WHERE s.parking_id = p.id AND s.vehicle_type = 'CAR'
  );

INSERT INTO parking_spaces
    (parking_id, space_code, space_name, vehicle_type, length_m, width_m, height_m)
SELECT p.id, 'B1', 'Bike Space 1', 'BIKE', p.length_m, p.width_m, p.height_m
FROM parking_listings p
WHERE p.vehicle_type IN ('BIKE', 'BOTH')
  AND NOT EXISTS (
      SELECT 1 FROM parking_spaces s
      WHERE s.parking_id = p.id AND s.vehicle_type = 'BIKE'
  );

-- Capacity mirrors the real active slot counts.
UPDATE parking_listings p
SET maximum_cars = (
        SELECT COUNT(*) FROM parking_spaces s
        WHERE s.parking_id = p.id AND s.vehicle_type = 'CAR' AND s.is_active
    ),
    maximum_bikes = (
        SELECT COUNT(*) FROM parking_spaces s
        WHERE s.parking_id = p.id AND s.vehicle_type = 'BIKE' AND s.is_active
    );

ALTER TABLE parking_listings
    ALTER COLUMN maximum_cars SET DEFAULT 0,
    ALTER COLUMN maximum_bikes SET DEFAULT 0,
    ALTER COLUMN maximum_cars SET NOT NULL,
    ALTER COLUMN maximum_bikes SET NOT NULL;

ALTER TABLE parking_listings
    DROP CONSTRAINT IF EXISTS parking_listings_capacity_non_negative;
ALTER TABLE parking_listings
    ADD CONSTRAINT parking_listings_capacity_non_negative
    CHECK (maximum_cars >= 0 AND maximum_bikes >= 0);

-- ============================================================
-- 3. Bookings reference a specific slot
-- ============================================================
ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS parking_space_id UUID REFERENCES parking_spaces(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_space ON bookings(parking_space_id);
CREATE INDEX IF NOT EXISTS idx_bookings_space_window
    ON bookings(parking_space_id, start_date, end_date)
    WHERE status IN ('ACCEPTED', 'PAYMENT_PENDING', 'CONFIRMED', 'ACTIVE');

-- ============================================================
-- 4. Double-booking guard: one occupying booking per slot per day
-- ============================================================
-- requestedStart <= existingEnd AND requestedEnd >= existingStart
-- (inclusive '[]' date ranges), enforced by PostgreSQL for the occupying
-- statuses only. NULL slots are excluded so legacy bookings are untouched.
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_no_overlap_per_space;
ALTER TABLE bookings
    ADD CONSTRAINT bookings_no_overlap_per_space
    EXCLUDE USING gist (
        parking_space_id WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    )
    WHERE (
        parking_space_id IS NOT NULL
        AND status IN ('ACCEPTED', 'PAYMENT_PENDING', 'CONFIRMED', 'ACTIVE')
    );
