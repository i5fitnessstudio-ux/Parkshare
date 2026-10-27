# ParkShare — Phase 2–5 (Listing, Booking & Payments E2E) Completion Report

**Status: ✅ PASS (end-to-end verified on emulator-5554)**

Date: 2026-09-24

---

## 1. What was delivered

### Backend — Dart Shelf REST API (`backend/`, port 8080)
Extends the Phase 1 API surface (auth moved unchanged from Phase 1) with **23 new endpoints** across 6 modules, all under the same `{success, message, data}` envelope:

| Module | Method | Path | Purpose |
|--------|--------|------|---------|
| Parkings | POST | `/api/parkings/` | Create listing (8-step wizard payload, dims in metres) |
| Parkings | GET | `/api/parkings/nearby` | Geo search (lat/long + radius) |
| Parkings | GET | `/api/parkings/owner/<ownerId>` | Owner's own listings (incl. draft status) |
| Parkings | GET | `/api/parkings/<parkingId>` | Detail (joined media + amenities) |
| Parkings | PUT | `/api/parkings/<parkingId>` | Update listing |
| Parkings | DELETE | `/api/parkings/<parkingId>` | Delete listing (cascade media/amenities) |
| Uploads | POST | `/api/uploads/` | Multipart parking photo upload → `/uploads/<file>` (GET) |
| Vehicles | POST/GET | `/api/vehicles/` | Add / list user vehicles (metre dimensions) |
| Vehicles | GET/PUT/DELETE | `/api/vehicles/<vehicleId>` | Read / update / delete a vehicle |
| Bookings | POST | `/api/bookings/` | Create booking; **overlapping dates → 409** |
| Bookings | GET | `/api/bookings/owner/<ownerId>` | Owner bookings (joined user/vehicle/payment) |
| Bookings | GET | `/api/bookings/user/<userId>` | User bookings |
| Bookings | GET | `/api/bookings/<bookingId>` | Booking detail |
| Bookings | PUT | `/api/bookings/<bookingId>/accept` | Accept (auto-accept path when `auto_approval`) |
| Bookings | PUT | `/api/bookings/<bookingId>/reject` | Reject |
| Payments | POST | `/api/payments/` | Simulated gateway: server-computed amount + txn id |
| Inbox | GET/POST | `/api/inbox/conversations` | List / create conversation |
| Inbox | GET/POST | `/api/inbox/conversations/<id>/messages` | List / send message |

- All booking/payment **amounts are computed server-side** (never sent by the client — lint-tested in `parking_draft_test.dart`).
- **Overlap rule** enforced in SQL-backed logic: a booking whose date range intersects an existing non-cancelled booking is rejected with **409**, verified E2E.
- Photo upload fix (see Known issues): full multipart body drain in `backend/lib/services/upload_service.dart` — uploads now persist (confirmed via DB media row + `201`).

### Database — PostgreSQL (`parkshare` @ 127.0.0.1:5432)
Migration `002_parking_booking.sql` added **9 tables**: `parking_listings`, `parking_media` (PHOTO only), `parking_amenities`, `vehicles`, `bookings`, `booking_status_history`, `payments`, `conversations`, `messages`.
- All dimensions are in **metres** with `CHECK (… > 0)` constraints; media stored as **remote/public URLs** (no blob storage).
- Booking statuses enforced (`REQUESTED → ACCEPTED → CONFIRMED → …`) with every transition written to `booking_status_history`; payments carry `transaction_id` + `paid_at` and a `SUCCESS/FAILED` constraint.

### Flutter app (`lib/`, feature-based structure)
- **Owner publish wizard** (`modules/owner/add_parking/`): 8 steps in an `IndexedStack` — Photos, Details, Location (map + pin + reverse-geocode), Dimensions (plain-number metres), Rental (Monthly/Yearly plans), Amenities (filter chips), About (vehicle type / access hours / auto-approval), Review → **Publish Parking**. `parking_draft.dart` validates in order and serializes the payload (no amount sent).
- **Owner side**: dashboard provider (earnings = sum of `SUCCESS` payments; Occupied = any `currentBooking`), parkings list, bookings tab + booking detail sheet (Call / Message / view payment txn), inbox tab + chat screen (real conversations over HTTP).
- **User side**: map (`flutter_map`) with search, real backend markers (green **P**), preview card, parking detail with **frontend fit check** (`fit_check_service.dart` → `Perfect Fit` / `Tight Fit` / `Doesn't Fit`), booking screen (vehicle pre-select, server amount), payment screen (pick payment method → simulated gateway → `Payment Successful` + Txn), user bookings tab (`Confirmed ✓`).
- **Vehicles** (`modules/vehicle/`): add/list vehicles with metre dimensions (drives the fit check).
- No AR/3D/FCM; all measurements in **metres**; photo picker is deterministic under `--dart-define=E2E_TEST=true` for E2E.

## 2. Test evidence

| Check | Result |
|-------|--------|
| `flutter analyze` | ✅ No issues found |
| `flutter test` | ✅ **22/22 pass** (fit-check 9, models 7, parking-draft 5, widget smoke 1) |
| **Integration test on emulator-5554** (`integration_test/e2e_flow_test.dart`, `--dart-define=E2E_TEST=true`) | ✅ **All tests passed (01:09 +1)** |

### Integration flow verified end-to-end on the emulator
1. Fresh install → Onboarding → Role Selection
2. **Vehicle User register** (Test Driver) → add vehicle **Honda Activa 6G / MH12AB1234 / 1.80×0.70×1.10 m**
3. Logout → **Parking Owner register** (Test Owner)
4. **Publish via the 8-step wizard**: Photos (deterministic picker → "1 of 4 photos added") → Details ("E2E Greenview …", "42 E2E Test Street, Bandra") → Location (auto-seeded **19.0760 / 72.8777**) → Dimensions (5.00 / 2.50 / 2.00) → Rental (Monthly **₹3,000**) → Amenities (**CCTV**) → About → Review shows real name + **₹3,000** → **Publish Parking**
5. Parking appears in the owner list; dashboard shows **Occupied** + ₹0 (fresh owner)
6. Logout → user login → Map → search → **real green P marker** → preview card → detail: **'Perfect Fit'** (bike 1.80×0.70×1.10 vs 5.00×2.50×2.00) and **'5.00 × 2.50 × 2.00 m'**
7. **Book** → server-computed **₹3,000** → **Pay ₹3,000** → **Payment Successful** (+ real Txn) → Bookings tab **'Confirmed ✓'**
8. **Overlap attempt** → same dates → backend **409** → UI **'Booking failed'** (no second row in DB)
9. Logout → owner login → Bookings: **Test Driver / E2E Greenview / Confirmed / MH12AB1234** → detail sheet **Txn + UPI** → chat → send **'Please share the entry code'** → bubble appears → Inbox lists **Test Driver**
10. Owner dashboard: **₹3,000** earnings, **Occupied**, recent-booking row **Test Driver**

### Run log (excerpt, `e2e_run.txt`, flushed 10:35:52)
```
00:00 +0: Phase 2-5: owner publish -> user map/fit/book/pay -> overlap 409 -> owner bookings/dashboard/chat
[E2E] boot: onboarding shown
[E2E] role selection shown
[E2E] user registered, home shown
[E2E] after Add vehicle tap: formTitle=1 fields=6 navBar=0
[E2E] vehicle submit settled
[E2E] vehicle added
[E2E] user logged out
[E2E] owner registered, dashboard shown
[E2E] parking published
01:09 +1: (tearDownAll)
01:09 +1: All tests passed!
```

### Database verification (post-run, `parkshare` DB — targeted by the run's unique `e2e<millis>` identifiers)
- Pre-run baseline: `users=130`, `vehicles=1`, and **0** rows in every Phase 2–5 table.
- **Users +2**: `Test Driver` (role `user`, `e2euser1790226283000@parkshare.com`, 10:34:49) and `Test Owner` (role `owner`, `e2eowner1790226283000@parkshare.com`, 10:35:05).
- **Parking +1 media +1 amenity**: `E2E Greenview 1790226283000` — `monthly_enabled`=true, **`monthly_rent`=3000**, `auto_approval`=true, `available`=true, **5.00 × 2.50 × 2.00 m**, lat **19.076 / lon 72.8777**; media URL `http://10.0.2.2:8080/uploads/y9sbXGLlXd4vC49Lmb0xQ.png` (upload persisted); amenity `CCTV`.
- **Vehicle +1**: Honda / Activa 6G / **MH12AB1234** / BIKE / 1.8×0.7×1.1 m / `is_primary`.
- **Booking +1**: **CONFIRMED**, amount **3000**, **MONTHLY**, 2026-09-24 → 2026-10-23, customer `Test Driver` (user), vehicle `MH12AB1234` — **exactly one** booking row, confirming the 409 overlap was rejected.
- **Status history +2**: `ACCEPTED` (10:35:34) → `CONFIRMED` (10:35:35) — auto-accept then payment-confirm path.
- **Payment +1**: **SUCCESS**, **UPI**, txn **TXN4T7RBU9NV9N9**, linked to the booking.
- **Inbox**: 1 conversation (linked to the E2E parking `381aa8c0…` + booking `9b71186b…`) with **1 message** — owner text `Please share the entry code` at 10:35:48.

## 3. Known issues / notes
- **External environment kill-loop (not an app bug)**: an external process (`adb shell am force-stop` + `cmd package uninstall` of `com.example.parkshare_new`) runs roughly every 2.5–4.5 min on emulator-5554, which killed several earlier integration runs ("did not complete"). Verified as environmental: no FATAL/ANR in logcat, runs progressed normally until force-killed. The reported run completed in the post-kill window.
- **Upload bug fixed**: earlier runs' photos failed to persist because the backend ignored trailing multipart parts; fixed by fully draining the request body in `upload_service.dart` (verified: `201` + media row with real URL).
- **PowerShell exit-code quirk**: `flutter test` run via PowerShell `*>` returns code 1 due to Gradle/JVM stderr warnings even when green; `flutter` itself reports "All tests passed!" (same as Phase 1).
- **Photo picker / GPS are deterministic only in E2E**: `--dart-define=E2E_TEST=true` swaps the photo picker for the bundled asset; the run pre-seeds the emulator GPS fix (`adb emu geo fix 72.8777 19.0760`) and pre-grants location permissions.
- **Payments are simulated** for the MVP: `POST /api/payments` creates a real txn id and marks the booking CONFIRMED (no external gateway).
- **No screenshot attached**: repeated external uninstalls left no stable app-visible state to capture; primary evidence is the passing run log + the row-level DB records above. Screen captures from runs on the emulator are written to `docs/e2e_shots/`.
- Diagnostic leftovers cleaned up: `tool/probe_server*.dart`, `tool/upload_repro.dart`, `tool/tcp_proxy.dart` removed; stale `probe_server 8099` process stopped. `docs/verify_phase2.sql` corrected to the live schema.

## 4. Ready for
Phase 6 (subscriptions / notifications / FCM, real payment gateway, release hardening) — schema evolution via new migrations.
## 5. Follow-up audit round — map, location, availability (2026-09-24)

Audit of the full owner-location ? user-map ? booking date flow against the mapping spec, plus fixes.

### Root causes found
1. **Dates ? map**: no serialization mismatch (`bookings.start_date/end_date` ? `startDate/endDate` YYYY-MM-DD verified end-to-end), but the geo `nearby` payload never attached the occupancy window, so availability dates never reached the user map/preview. Fixed server-side: `nearby` now returns `currentBooking` + `availableFrom`.
2. **Owner location step**: no search field; "Use My Current Location" read a possibly-stale/absent GPS point without requesting permission or handling denied/disabled; drag-map updated coordinates but never reverse-geocoded.
3. **User search UX**: geocode fired on every keystroke, no debounce/stale-response protection.
4. **Amenities**: tiny chips + an unwanted "Others" option.

### Changes (backend)
- `backend/lib/models/parking.dart` — amenity list rebuilt: removed `Others`, added `Covered Parking`, `24/7 Access`, `Gate Access`, `Wheelchair Accessible`, `Two Wheeler Allowed`, `Car Allowed` (existing labels kept, DB rows stay valid).
- `backend/lib/services/parking_service.dart` — `nearby()` attaches `currentBooking` + `availableFrom` (same window data as the owner list) so booking dates reach the user map.

### Changes (Flutter)
- `lib/modules/owner/add_parking/parking_draft.dart` — amenity list mirrored 1:1 with backend.
- `lib/modules/owner/add_parking/steps/amenities_step.dart` — large tappable grid tiles (icon + label + selected state, 2-column responsive, no overflow); still `FilterChip`-based so the E2E finder is unchanged.
- `lib/modules/owner/add_parking/steps/location_step.dart` — added location search (debounced 400 ms + stale-guard), `Use My Current Location` now calls `LocationProvider.refresh()` (real permission request; denied/disabled/unavailable ? clear snackbar; no hard-coded fallback), drag-map reverse-geocodes on settle (350 ms debounce, stale-dropped) and shows the resolved address; back-fills the draft address only when empty; timers/controllers disposed.
- `lib/core/services/location_search_service.dart` — added non-throwing `reverseGeoCode(lat, lng)`.
- `lib/modules/user/map/user_map_tab.dart` — search debounced 350 ms with sequence guard; preview card shows "Currently booked · free from <date>" from the new nearby fields.
- `lib/modules/user/parking/parking_detail_screen.dart` — always re-fetches the listing by `parkingId` (falls back to the passed object only on network failure) so "Book This Parking" never uses a stale snapshot.

### Verification
- `dart analyze` (backend): ? No issues found.
- `flutter analyze`: ? No issues found.
- `flutter test`: ? 22/22 pass.
- Live API check (`GET /api/parkings/nearby?lat=19.0760&lng=72.8777&radiusKm=5`, owner token): results now carry the booking window — e.g. `E2E Greenview 1790227158583` ? `currentBooking=2026-09-24?2026-10-23`, `availableFrom=2026-10-24`.
- Backend restarted with the new code (`dart run bin/server.dart`); `/health` 200.
- App rebuilt + installed on emulator-5554; launched into the foreground (killed shortly after by the external force-stop loop — same environmental hazard as §3).
