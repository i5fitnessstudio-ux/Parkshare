-- ParkShare Phase 2-5 post-run DB evidence (run from psql against the parkshare DB)
SELECT 'users' AS tbl, count(*) FROM users
UNION ALL SELECT 'parking_listings', count(*) FROM parking_listings
UNION ALL SELECT 'parking_media', count(*) FROM parking_media
UNION ALL SELECT 'parking_amenities', count(*) FROM parking_amenities
UNION ALL SELECT 'vehicles', count(*) FROM vehicles
UNION ALL SELECT 'bookings', count(*) FROM bookings
UNION ALL SELECT 'booking_status_history', count(*) FROM booking_status_history
UNION ALL SELECT 'payments', count(*) FROM payments
UNION ALL SELECT 'conversations', count(*) FROM conversations
UNION ALL SELECT 'messages', count(*) FROM messages
ORDER BY tbl;

-- Latest published parking (the E2E one: name contains 'E2E Greenview')
SELECT id, parking_name, city, address, monthly_enabled, monthly_rent,
       length_m, width_m, height_m, latitude, longitude, available, created_at
FROM parking_listings ORDER BY created_at DESC LIMIT 3;

-- Its media + amenities
SELECT pl.id, pl.parking_name,
       (SELECT count(*) FROM parking_media pm WHERE pm.parking_id = pl.id) AS media_count,
       (SELECT count(*) FROM parking_amenities pa WHERE pa.parking_id = pl.id) AS amenities_count
FROM parking_listings pl ORDER BY created_at DESC LIMIT 3;

-- Latest booking with joined customer + vehicle + payment
SELECT b.id, b.status, b.amount, b.rental_type, b.start_date, b.end_date,
       u.name AS customer, u.role AS customer_role,
       v.registration_number, v.model, v.length_m, v.width_m, v.height_m,
       p.id AS payment_id, p.payment_status, p.transaction_id, p.payment_method
FROM bookings b
JOIN users u ON u.id = b.user_id
JOIN vehicles v ON v.id = b.vehicle_id
LEFT JOIN payments p ON p.booking_id = b.id
ORDER BY b.created_at DESC LIMIT 3;

-- Status history for the latest booking
SELECT bh.booking_id, bh.status, bh.created_at
FROM booking_status_history bh
ORDER BY bh.created_at DESC LIMIT 6;

-- Latest conversation(s) + message count
SELECT c.id, c.user_id, c.owner_id, c.parking_id,
       (SELECT count(*) FROM messages m WHERE m.conversation_id = c.id) AS message_count
FROM conversations c ORDER BY c.created_at DESC LIMIT 3;

-- Last messages (should include the E2E chat text)
SELECT m.conversation_id, m.sender_id, m.body, m.created_at
FROM messages m ORDER BY m.created_at DESC LIMIT 5;