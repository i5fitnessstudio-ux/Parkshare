# ParkShare — Phase 2–5 (Owner Listings, Map & Book, Fit Check, Payments) Completion Report

**Status: ✅ PASS (end-to-end verified on emulator-5554, REST suite 41/41, E2E green)**

Date: 2026-09-24

---

## 1. Executive summary

Phase 2–5 delivers the complete parking marketplace loop on top of Phase 1 auth:

- **Parking Owner** registers → records a real parking (8-step wizard: photos → location → details → dimensions → rent → amenities → review → publish) → sees it on the dashboard, gets real bookings, real earnings, and can Call / Message / review the customer's booking in detail.
- **Vehicle User** adds real vehicle records → searches the OSM map, uses GPS or a searched location → sees **real green parking markers** → opens a detail card → asks **"Does my vehicle fit?"** (pure dimension comparison, validated on the client AND the server) → books a date range → the server computes the amount → simulated payment → **CONFIRMED** → the booking shows in both the user's and the owner's joined views, and a real chat conversation is opened between the two parties.
- Duplicate/overlapping bookings on the same parking are **rejected by the backend (HTTP 409)**.

Everything is wired to the real PostgreSQL backend (port 8080, Docker-free); **no fake or hard-coded data** is used anywhere in the product path — the review screen shows the real draft, the map shows real published parkings, bookings join real user/parking/vehicle/payment rows, and dashboard earnings are summed from real `payments` rows.

## 2. Stack at a glance

| Layer | Technology |
|---|---|
| App | Flutter (Android + iOS), Provider state management, `flutter_secure_storage` |
| Map | `flutter_map` (OpenStreetMap tiles), `geolocator`, `geocoding`, `latlong2` |
| Backend | Dart + Shelf on **:8080**, BCrypt + JWT, multipart photo upload |
| DB | PostgreSQL 17 (`parkshare` @ 127.0.0.1:5432), idempotent migrations |
| Tests | 22 Flutter unit/smoke tests, **41-check backend REST suite**, full emulator E2E |

## 3. Backend API surface (all real, all exercised)

| Method | Route | Purpose |
|---|---|---|
| GET | `/health` | Liveness probe |
| POST | `/api/auth/register`, `/login`, `/refresh`, `/logout` | Phase 1 auth (unchanged, still passing) |
| GET | `/api/auth/me` | Current session user |
| POST | `/api/auth/forgot-password`, `/verify-reset-otp`, `/reset-password` | OTP password reset (dev OTP) |
| POST | `/api/vehicles` | Save a vehicle (Bike / Car) |
| GET | `/api/vehicles`, `/{id}`, PUT `/{id}`, DELETE `/{id}` | Manage vehicles |
| POST | `/api/uploads` | Multipart photo upload (JPG/PNG/WEBP) → URL |
| POST | `/api/parkings` | Publish a listing (draft cleared, server-validated) |
| GET | `/api/parkings/nearby?lat=&lng=&radiusKm=` | Real marker feed for the user map |
| GET | `/api/parkings/owner/{ownerId}`, `/{parkingId}` | Owner list / single listing |
| PUT | `/api/parkings/{parkingId}` | Edit listing (full payload) |
| POST | `/api/bookings` | Create booking; **409 on any date overlap** with an active/confirmed booking |
| GET | `/api/bookings/owner/{ownerId}`, `/user/{userId}`, `/{bookingId}` | **Joined** user+parking+vehicle+payment rows |
| PUT | `/api/bookings/{bookingId}/accept` / `/reject` | Owner decisions |
| POST | `/api/payments` | Simulated gateway; SUCCESS → booking **CONFIRMED** (real `TXN…` id) |
| POST | `/api/inbox/conversations` | Ensure-or-create real conversation (per parking+booking) |
| GET | `/api/inbox/conversations` | Conversation list with unread counts |
| POST/GET | `/api/inbox/conversations/{id}/messages` | Real message thread |
| GET | `/uploads/{file}` | Serves uploaded parking photos |

## 4. Database (PostgreSQL)

13 tables across two migrations (`001_auth.sql`, `002_parking_booking.sql`):
`users`, `refresh_tokens`, `password_reset_otps`, `parking_listings`, `parking_media`,
`parking_amenities`, `vehicles`, `bookings`, `booking_status_history`, `payments`,
`conversations`, `messages`, `schema_migrations`.

- Dimensions are stored as **plain number metres** (`length_m`, `width_m`, `height_m` — all `CHECK (> 0)`); entrance dimensions optional.
- Rents: `monthly_rent` / `yearly_rent` with `CHECK (… > 0)`; enabled flags gate validation.
- Amenities are **per-row in `parking_amenities`** — an absent row means "not selected" (no fake lists).
- Photos are stored as **remote URLs only** (`parking_media.photo_url`) — the emulator fetches them from the dev server exactly like a production CDN URL would be fetched.
- Booking `status` transitions mirror the requirement: `REQUESTED → ACCEPTED → PAYMENT_PENDING → CONFIRMED` (→ `ACTIVE` / `COMPLETED` / `CANCELLED` / `REJECTED`), with every transition recorded in `booking_status_history`.

Post-E2E state (real rows): 1 listing, 1 photo, 1 amenity, 1 vehicle, 1 booking
**CONFIRMED ₹3,000 MONTHLY**, 1 payment, 1 conversation, 1 message.

## 5. The upload fix (critical bug found & fixed during E2E)

The first symptom was that publishing failed intermittently after the first photo. Root cause in
`backend/lib/services/upload_service.dart`: the multipart parser **`break`-ed the form-data stream
loop too early**, leaving the multipart trailer un-consumed, which closed the connection mid-write
(empty responses, `SocketException` on retry). Fix: **drain the entire `form.formData` stream** before
building the response. Verified three ways — `curl`, `dart:io` client, and `package:http` client — all
return HTTP 201 with a `{ "url": "/uploads/….png" }` payload, and the E2E now uploads, publishes and
displays the photo reliably.

## 6. Owner add-parking wizard (8 steps, real draft)

`AddParkingScreen` + `ParkingDraft` (a single in-memory real draft object survives the wizard):

1. **Photos** — camera **or** gallery, max **4**, preview + remove; **photos only** (no video). Only URLs are persisted.
2. **Location** — OSM map tap-to-pin with a search bar; GPS fix seeds the pin; pan-debounced (~600 ms) so marker placement is stable; step is gated (`active: _step == 2`) so the map never polls while hidden.
3. **Details** — name, address, city, state, pincode, landmark, type (Non-covered / Covered), hours, description, conditions.
4. **Dimensions** — depth/width/height (metres, plain numbers, `> 0`), entrance dims **optional**.
5. **Rental** — at least **one enabled plan**, enabled rent `> 0` (client validated, server re-validated).
6. **Amenities** — multi-select checkboxes persisted per-row.
7. **Review** — shows the **real draft** (real photo thumbnails, real values, computed plan label); nothing is faked or hard-coded.
8. **Publish** — uploads photos (`POST /api/uploads`) → `POST /api/parkings` (server validates and computes; **the client never sends an amount**) → clears the draft → dashboard refreshes (`[publish] created id=…` now real, print removed in final cleanup).

Vehicle type on the listing: `BIKE` / `CAR` / `BOTH`.

## 7. User map, search & markers (real data)

`UserMapTab` + `UserMapProvider` + `LocationProvider`:

- **Permission handling without crashes**: `denied` → persuade banner; `disabled` → message; `unavailable` → fallback; the first frame never crashes because the location check is non-crashy (`checkOnly`).
- **Search bar** (debounced `geocoding`) — selecting a suggestion **overrides GPS** (map re-centres to the searched point); **"Current Location" restores GPS**.
- **Real green `P` markers** from `GET /api/parkings/nearby` (E2E-verified with the published listing). Tapping a marker opens a preview card → "View →" detail.
- **Empty state**: when the searched area has no parkings the map shows **"No parking spaces available nearby"** (verified).
- ~600 ms pan debounce keeps search/recentre/back-to-GPS from fighting the user's pan.

## 8. Fit check — pure dimension comparison (validated client + server)

`FitCheckService` (shared logic in `lib/core/services/fit_check_service.dart`, mirrored on the
backend in `booking_service`/fit helpers):

| Margin added to vehicle | `length + 0.50 m`, `width + 0.30 m`, `height + 0.15 m` |
|---|---|
| **FIT** | vehicle (with margins) fits inside parking dims |
| **TIGHT_FIT** | fits, but entrance dims are smaller than parking dims (when entrance provided) |
| **DOES_NOT_FIT** | otherwise |

The detail screen computes it live against the driver's selected vehicle; the **backend re-validates
on booking create** and rejects `DOES_NOT_FIT` with a 400 so a non-fitting vehicle can never be
booked. No AR — a deliberate, requirement-compliant design.

## 9. Booking lifecycle, payments & overlap protection

- User picks the parking → **Book This Parking** → date-range picker (client-side estimate; **final amount computed by the server**) → `POST /api/bookings`.
- Auto-approved listings go straight to payment: `ACCEPTED → PAYMENT_PENDING →` simulated **UPI/Card/NetBanking** payment → `SUCCESS` → **CONFIRMED** with a real `TXN…` transaction id. Owner-only decision listings stay `REQUESTED` until the owner accepts/rejects.
- **Overlap protection is backend-enforced**: a second booking whose [start, end) intersects any other booking in `ACCEPTED / PAYMENT_PENDING / CONFIRMED / ACTIVE` on the same parking is rejected with **409** (`"This parking is already booked for the selected dates."`). Verified in the REST suite AND in the E2E.
- The user's Bookings tab shows "Confirmed ✓"; the **owner's Bookings tab shows the same booking with the real customer, vehicle and payment joined in**.

## 10. Owner bookings — real joined data + Call / Message / View Details

`OwnerBookingListTab` + `OwnerBookingDetailSheet`:

- Cards render real rows: customer name + phone, parking name + address, vehicle type, brand/model/registration, plan, dates and status.
- Detail sheet groups **CUSTOMER / PARKING / VEHICLE / RENTAL & DATES / PAYMENT** — the payment block shows the real `TXN…` id and method from `payments`.
- **Call** → `tel:` via `url_launcher` (falls back gracefully when no phone on record).
- **Message** → `InboxProvider.ensureConversation(...)` creates/reuses a **real conversation** and opens the chat screen; the other party sees it in their Inbox.

## 11. Chat / inbox (real conversations)

`ChatScreen` + `InboxProvider` + `inbox` tables: sending a message inserts a row in `messages`;
both the owner (via booking sheet › Message) and the user (via booking card › Message) see the same
thread in their **Inbox tab** with unread states. E2E sends "Please share the entry code" and
asserts the bubble appears and the owner Inbox lists the conversation.

## 12. Owner dashboard (real earnings)

`OwnerDashboardProvider` + `OwnerDashboardScreen` — Overview shows real counts (parkings,
available/occupied), **Total Earnings = SUM(payments.amount)** where the booking is not cancelled,
and Recent Bookings with customer names + status. After the E2E payment the dashboard shows
**₹3,000 total earnings** and the parking turns **Occupied** — both asserted in the E2E.

## 13. Verification — static analysis & unit tests

| Check | Result |
|---|---|
| `flutter analyze` | ✅ No issues found |
| `dart analyze` (backend) | ✅ No issues found |
| `flutter test` (VM) | ✅ **22/22** unit/smoke tests (fit-check matrix, `ParkingDraft` validation & payload, models, widget boot) |
| Backend `/health` | ✅ 200 `{status:"ok"}` |
| Backend running | ✅ alive on :8080 during the whole window (background shell, request log captured) |

## 14. Verification — REST suite (41/41 PASS)

`tool/rest_suite.ps1` runs against the live backend + real DB and covers, in order: health;
register×2; duplicate email **409**; wrong-role login **403**; wrong password **401**; login;
refresh rotation; `/me`; logout; **revoked refresh reuse rejected**; forgot-password dev OTP;
verify; reset; **OTP reuse rejected**; re-login with the new password; vehicle create/list;
**invalid dimensions 400**; **multipart photo upload 201**; parking publish with the photo;
draft-cleared + no client amount; **enabled plan without rent 400**; parking get/owner/nearby
(found) / far-away nearby (empty); booking create (auto-approved `ACCEPTED`); **overlap 409**;
payment with real `TXN…`; booking → **CONFIRMED**; joined user+parking+vehicle+payment;
owner/user booking lists; conversation ensure/list; send message; message thread; photo served
over HTTP; parking update; vehicle delete — **all 41 pass**.

## 15. Verification — full emulator E2E (green)

`integration_test/e2e_flow_test.dart` on **emulator-5554** (Pixel 8, API 37) with
`--dart-define=E2E_TEST=true` (deterministic GPS + photo picker behind the define; real backend
at `10.0.2.2:8080`; real PostgreSQL):

1. Fresh install → Onboarding → Role selection.
2. **Vehicle User** registers → adds vehicle (Honda Activa 6G, 1.80 × 0.70 × 1.10 m) → logs out.
3. **Parking Owner** registers → 8-step wizard → real photo upload (HTTP 201) → published listing appears on the dashboard.
4. **User** logs in → map: searched-location override → **real empty state** → "Current Location" restore → **real green marker** → preview card → detail: **Perfect Fit**, `5.00 × 2.50 × 2.00 m`, vehicle pre-selected → **Book This Parking** → server amount **₹3,000** → **Pay ₹3,000** → **Payment Successful** with `Txn TXN…` → user Bookings shows **Confirmed ✓**.
5. **Overlap attempt on the same parking → 409 snackbar; no second booking.**
6. **User logs out → Owner logs in** → Bookings tab: real card (Test Driver, E2E Greenview, Honda Activa 6G · MH12AB1234, Confirmed) → detail sheet (real Txn) → **Message** → real conversation → sends "Please share the entry code" (bubble asserted) → owner Inbox lists the conversation → Dashboard shows **₹3,000** earnings + **Occupied**.
7. **All pass**: consecutive green runs — `01:10 +1: All tests passed!` (e2e_final3) and `00:58 +1: All tests passed!` (e2e_final4, run during the screenshot capture).

Screenshots captured on-device during the final run (`docs/e2e_shots/`, OCR-identified below).

## 16. Screenshot gallery (captured live on emulator-5554)

All frames below were pulled from the device screen during the **final green E2E run**
(`00:58 +1: All tests passed!`), with OCR captions cross-checked against the app code
and the E2E assertions. Full set in `docs/e2e_shots/`.

| # | File (`docs/e2e_shots/`) | What it shows |
|---|---|---|
| 1 | `01_role_selection.png` | Role selection — Parking Owner / Vehicle User |
| 2 | `02_add_vehicle.png` | Add Vehicle (real data): Honda Activa 6G · MH12AB1234 · L 1.80 × W 0.70 × H 1.10 m |
| 3 | `03_user_home_vehicle.png` | Vehicle User home — saved vehicle card (PRIMARY), Map / Bookings / Vehicles / Inbox |
| 4 | `04_wizard_address.png` | Owner wizard **2/8** — Name & address (real draft form) |
| 5 | `05_wizard_dimensions.png` | Wizard **4/8** — plain-metre dims L 5.00 × W 2.50 × H 2.00; optional entrance 2.20 × 2.80 |
| 6 | `06_wizard_about.png` | Wizard **7/8** — type, accepted vehicles, auto-approve toggle, hours, house rules |
| 7 | `07_dashboard_published.png` | Owner dashboard after **real publish** — listing live, "…published!" snackbar, Available badge |
| 8 | `08_map_search_suggestions.png` | User map — search bar with geocoding suggestions that override GPS |
| 9 | `09_payment_screen.png` | Simulated gateway — E2E Greenview, Monthly 24 Sep–23 Oct, **₹3,000 server-computed**, UPI/Card/NetBanking, "Pay ₹3,000" |
| 10 | `10_map_conflict_409.png` | Backend overlap protection — second booking on the same dates → **409 "…already booked for the selected dates."** |
| 11 | `11_chat_sent.png` | Owner → **Message** opens a real conversation; "Please share the entry code" sent (timestamped bubble) |

The **parking-detail fit-check screen** ("Perfect Fit", dims `5.00 × 2.50 × 2.00 m`) has a very
short on-screen dwell time and was not caught by the 3 s sampler; it is verified twice by the
E2E assertions and described in §8 above (pure dimension comparison, client + server).

## 17. Known notes & how to run

- Location permission grants are wiped on reinstall; the E2E uses the deterministic
  `E2E_TEST` location branch (Mumbai 19.0760, 72.8777), which also matches the emulator geo fix.
- OSM tile servers warn about usage policy in debug logs — expected, harmless.
- SQLite/ar: no — the app talks only to the real API; unit tests use the VM with no network.
- **Run the backend**: `cd backend; dart run bin/server.dart` (port from `PORT` env / `.env`) — migrations auto-apply.
- **Run the checks**: `flutter analyze`; `flutter test`; `powershell -File tool\rest_suite.ps1`; then the emulator E2E with a clean DB + `pm clear` as described in `integration_test/e2e_flow_test.dart`.
- The upload fix lives in `backend/lib/services/upload_service.dart`; client debug prints were removed in the final cleanup (`flutter analyze` stays at "No issues found").