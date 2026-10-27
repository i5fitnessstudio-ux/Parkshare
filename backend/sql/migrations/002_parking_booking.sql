-- Phase 2/3/4: Parking listings, vehicles, bookings, payments, inbox.
-- All dimensions in METERS. Media/photo storage: remote/public URLs only.

-- ============================================================
-- 1. Parking listings
-- ============================================================
CREATE TABLE IF NOT EXISTS parking_listings (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    parking_name          TEXT NOT NULL,
    address               TEXT NOT NULL,
    city                  TEXT,
    state                 TEXT,
    pincode               TEXT,
    landmark              TEXT,

    latitude              DOUBLE PRECISION NOT NULL,
    longitude             DOUBLE PRECISION NOT NULL,

    parking_type          TEXT NOT NULL DEFAULT 'NON_COVERED'
                          CHECK (parking_type IN ('NON_COVERED', 'COVERED')),

    length_m              DOUBLE PRECISION NOT NULL CHECK (length_m > 0),
    width_m               DOUBLE PRECISION NOT NULL CHECK (width_m > 0),
    height_m              DOUBLE PRECISION NOT NULL CHECK (height_m > 0),

    entrance_length_m     DOUBLE PRECISION,
    entrance_width_m      DOUBLE PRECISION,
    entrance_height_m     DOUBLE PRECISION,

    vehicle_type          TEXT NOT NULL DEFAULT 'BOTH'
                          CHECK (vehicle_type IN ('BIKE', 'CAR', 'BOTH')),

    monthly_enabled       BOOLEAN NOT NULL DEFAULT FALSE,
    monthly_rent          DOUBLE PRECISION CHECK (monthly_rent IS NULL OR monthly_rent > 0),
    yearly_enabled        BOOLEAN NOT NULL DEFAULT FALSE,
    yearly_rent           DOUBLE PRECISION CHECK (yearly_rent IS NULL OR yearly_rent > 0),

    access_hours          TEXT NOT NULL DEFAULT '24/7',
    description           TEXT NOT NULL DEFAULT '',
    conditions            TEXT NOT NULL DEFAULT '',

    available             BOOLEAN NOT NULL DEFAULT TRUE,
    auto_approval         BOOLEAN NOT NULL DEFAULT FALSE,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_parking_owner ON parking_listings(owner_id);
CREATE INDEX IF NOT EXISTS idx_parking_geo ON parking_listings(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_parking_available ON parking_listings(available);

-- ============================================================
-- 2. Parking media (PHOTO only; NO video fields in this project)
-- ============================================================
CREATE TABLE IF NOT EXISTS parking_media (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parking_id    UUID NOT NULL REFERENCES parking_listings(id) ON DELETE CASCADE,
    media_type    TEXT NOT NULL DEFAULT 'PHOTO' CHECK (media_type IN ('PHOTO')),
    url           TEXT NOT NULL,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_parking_media_parking ON parking_media(parking_id);

-- ============================================================
-- 3. Parking amenities (one row per amenity)
-- ============================================================
CREATE TABLE IF NOT EXISTS parking_amenities (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parking_id  UUID NOT NULL REFERENCES parking_listings(id) ON DELETE CASCADE,
    amenity     TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_parking_amenities_parking ON parking_amenities(parking_id);

-- ============================================================
-- 4. User vehicles (Vehicle User saves own vehicle for fit check)
-- ============================================================
CREATE TABLE IF NOT EXISTS vehicles (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    vehicle_type         TEXT NOT NULL DEFAULT 'CAR' CHECK (vehicle_type IN ('BIKE', 'CAR')),
    brand                TEXT NOT NULL,
    model                TEXT NOT NULL,
    registration_number  TEXT NOT NULL,
    photo_url            TEXT,
    length_m             DOUBLE PRECISION NOT NULL CHECK (length_m > 0),
    width_m              DOUBLE PRECISION NOT NULL CHECK (width_m > 0),
    height_m             DOUBLE PRECISION NOT NULL CHECK (height_m > 0),
    is_primary           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vehicles_user ON vehicles(user_id);

-- ============================================================
-- 5. Bookings
-- ============================================================
CREATE TABLE IF NOT EXISTS bookings (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parking_id   UUID NOT NULL REFERENCES parking_listings(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    owner_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    vehicle_id   UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,

    rental_type  TEXT NOT NULL CHECK (rental_type IN ('MONTHLY', 'YEARLY')),
    start_date   DATE NOT NULL,
    end_date     DATE NOT NULL,
    amount       DOUBLE PRECISION NOT NULL,

    status       TEXT NOT NULL DEFAULT 'REQUESTED' CHECK (status IN (
                   'REQUESTED','ACCEPTED','REJECTED','PAYMENT_PENDING',
                   'CONFIRMED','ACTIVE','COMPLETED','CANCELLED')),

    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_bookings_parking ON bookings(parking_id);
CREATE INDEX IF NOT EXISTS idx_bookings_owner ON bookings(owner_id);
CREATE INDEX IF NOT EXISTS idx_bookings_user ON bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status);

-- ============================================================
-- 6. Booking status history
-- ============================================================
CREATE TABLE IF NOT EXISTS booking_status_history (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id  UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    status      TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_booking_history_booking ON booking_status_history(booking_id);

-- ============================================================
-- 7. Payments (simulated gateway for MVP)
-- ============================================================
CREATE TABLE IF NOT EXISTS payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id      UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    owner_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount          DOUBLE PRECISION NOT NULL,
    payment_method  TEXT NOT NULL DEFAULT 'UPI',
    transaction_id  TEXT NOT NULL,
    payment_status  TEXT NOT NULL DEFAULT 'PENDING'
                    CHECK (payment_status IN ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    paid_at         TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_payments_booking ON payments(booking_id);
CREATE INDEX IF NOT EXISTS idx_payments_owner ON payments(owner_id);

-- ============================================================
-- 8. Inbox: conversations + messages
-- ============================================================
CREATE TABLE IF NOT EXISTS conversations (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    owner_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parking_id       UUID REFERENCES parking_listings(id) ON DELETE SET NULL,
    booking_id       UUID REFERENCES bookings(id) ON DELETE SET NULL,
    last_message_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, owner_id, booking_id)
);

CREATE INDEX IF NOT EXISTS idx_conversations_user ON conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_owner ON conversations(owner_id);

CREATE TABLE IF NOT EXISTS messages (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id  UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body             TEXT NOT NULL,
    read_at          TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at);