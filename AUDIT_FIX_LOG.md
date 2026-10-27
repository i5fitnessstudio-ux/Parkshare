# ParkShare — Security Remediation Log (`AUDIT_FIX_LOG.md`)

**Companion to:** `AUDIT_REPORT.md` (the audit, written **before** any change, with exact file/line references).
**Toolchain used for every command below:** Flutter 3.47.1 · Dart 3.13.1 · PostgreSQL 17 (`postgresql-x64-17`, Running) · Android SDK build-tools 36.0.0 · Windows 10.0.26200.
**Date:** 2026-10-05.
**Repo state:** `fatal: not a git repository` — there is no VCS here, so every change below is a local working-tree edit. Nothing was committed, reverted or rewritten wholesale.

---

## 0. How to reproduce every claim in this document

```powershell
# Backend analysis + tests (the backend now HAS a test suite - it had none)
cd C:\Parkshare_new\backend
dart pub get
dart analyze                 # -> No issues found!
dart test                    # -> All tests passed!  (129 tests, 7 files)

# App analysis + tests
cd C:\Parkshare_new
flutter pub get
flutter analyze              # -> No issues found!
flutter test                 # -> All tests passed!  (127 tests)

# Live backend
$env:ALLOW_DEV_OTP='true'    # local dev run only; SMTP is not configured here
cd C:\Parkshare_new\backend; dart run bin/server.dart
# -> "ParkShare API listening on http://0.0.0.0:8080"
Invoke-WebRequest http://localhost:8080/health -UseBasicParsing

# Release builds are FAIL-CLOSED until a keystore is configured
cd C:\Parkshare_new
flutter build apk --release         # -> BUILD FAILED (exit 1), prints the remediation text
flutter build appbundle --release   # -> BUILD FAILED (exit 1), same reason
flutter build apk --debug           # -> Built build\app\outputs\flutter-apk\app-debug.apk  (no keystore needed)
```

`.env` values are **never** printed anywhere in this document or in any test. Only `FOUND` / `NOT SET` style facts and booleans are asserted.

---

## 1. Result summary

| ID | Finding | Severity | Status | Primary change |
|---|---|---|---|---|
| C-01 | UPI confirm self-asserted, txn IDs fabricated, `SUCCESS` manufactured | **CRITICAL** | **FIXED** | `backend/lib/services/payment_service.dart:227-321` |
| C-02 | Owner earnings derived client-side | **CRITICAL** | **FIXED** | `payment_service.dart:639-708` + `routes/payment_routes.dart:154-158` |
| H-01 | Hard-coded dev JWT secret, no production guard | **HIGH** | **FIXED (fail-closed)** | `lib/config/config.dart:84-88,194-242`, `bin/server.dart:49-65` |
| H-02 | OTP printed to console + returned to client | **HIGH** | **FIXED** | `auth_service.dart:386-396`, `lib/core/constants/dev_flags.dart` |
| H-03 | Account enumeration in forgot/verify | **HIGH** | **FIXED** | `auth_service.dart:18-24,321-331` |
| H-04 | Access tokens had no `exp`/`iat` | **HIGH** | **FIXED** | `auth_service.dart:631-655`, `middleware/auth_middleware.dart:78-81` |
| H-05 | No rate limiting on OTP/auth | **HIGH** | **FIXED** | `middleware/middleware.dart:199-238`, `routes/auth_routes.dart` |
| H-06 | Release build signed with the debug keystore | **HIGH** | **FIXED (fail-closed)** | `android/app/build.gradle.kts` |
| H-07 | `applicationId = com.example.parkshare_new` | **HIGH** | **REPORTED ONLY** (by instruction) | see §9 |
| H-08 | Release build can leak dev OTP UI / dev API URL | **HIGH** | **FIXED** | `lib/core/constants/dev_flags.dart`, `lib/core/constants/api_constants.dart:40-61` |
| M-01 | CORS `*` unconditionally | MEDIUM | FIXED | `middleware.dart:136-166`, `config.dart:148-163` |
| M-02 | Upload trusted the client's `Content-Type` | MEDIUM | FIXED | `storage/media_storage.dart:147-238`, `services/upload_service.dart` |
| M-03 | `startsWith` traversal guard; URLs built from `Host` | MEDIUM | FIXED (+ **2 real bugs** found, see §5) | `media_storage.dart:53-89`, `config.dart:227-232` |
| M-04 | No security response headers | MEDIUM | FIXED | `middleware.dart:174-190`, `media_storage.dart:83-99` |
| M-05 | `errorMiddleware` printed exception + stack | MEDIUM | FIXED (prod-redacted) | `middleware.dart:106-124` |
| M-06 | `logRequests()` unconditionally on | MEDIUM | FIXED | `config.dart:46-50`, `bin/server.dart:40-42` |
| M-07 | `Random()` for security identifiers | MEDIUM | FIXED | `media_storage.dart:35`, `auth_service.dart:54`, `payment_service.dart` |
| M-08 | OTP "verified" state reusable indefinitely | MEDIUM | FIXED | `auth_service.dart:502-560`, migration 005 |
| M-09 | Live `.env` in the package | MEDIUM | MITIGATED (rotating values is the owner's action) | `.gitignore:36-46`, `backend/.gitignore:6-7` |
| M-10 | 6-char password minimum, no lockout | MEDIUM | FIXED | `config.dart:110-112`, `auth_service.dart:35-50` |
| M-11 | No index on `otp_hash`, no cleanup | MEDIUM | FIXED | `sql/migrations/005_security_fixes.sql:100-105` |
| M-12 | `viewerId: ''` on `GET /api/parkings/{id}` | MEDIUM | FIXED | `routes/parking_routes.dart`, `auth_middleware.dart:105-116` |
| M-13 | No rate limiting anywhere | MEDIUM | FIXED | `middleware.dart:199-238` |
| M-14 | No refresh-token reuse detection | MEDIUM | PARTIAL — rotation + revocation hardened; **documented residual** (§9) | `auth_service.dart` |
| M-15 | `allowBackup` not disabled | MEDIUM | FIXED | `android/app/src/main/AndroidManifest.xml` |
| M-16 | No HTTPS/TLS enforcement | MEDIUM | INFRASTRUCTURE (documented; `PUBLIC_BASE_URL` is now required in production) | `config.dart:227-232` |
| M-17 | Owner phone/UPI exposed to any authenticated user | MEDIUM | FIXED (minimised to what the payer must see) | `models/booking.dart:249-254` |
| L-01 | Generated artifacts in the package | LOW | MITIGATED (git-ignored; **not deleted** — the user's files) | `.gitignore:43-47` |
| L-02 | `local.properties` SDK path | LOW | REPORTED ONLY | — |
| L-03 | Google Sign-In missing | LOW | REPORTED ONLY | — |
| L-04 | Esri UA is the placeholder package name | LOW | PARTIAL — UA now a real, stable string; provider/attribution unchanged | `lib/core/constants/map_tiles.dart`, `lib/core/constants/app_identity.dart` |
| L-05 | `tool/rest_suite.ps1` hardcodes a test password | LOW | REPORTED ONLY (dev-only script, not in the app binary) | — |
| L-06 | Dev OTP UI in release | LOW | FIXED | `dev_flags.dart` |
| L-07 | URI string concatenation | LOW | REPORTED (all ids are server-issued UUIDs) | — |
| L-08 | Dead branches | LOW | REPORTED ONLY | — |
| L-09 | Outdated packages | LOW | REPORTED — no security-advisory bumps available | — |
| L-10 | Backend had **zero** tests | LOW | **FIXED — 129 tests** | `backend/test/` |
| L-11 | `print()` used directly | LOW | FIXED where it leaked (H-02); remaining prints are deliberate diagnostics | — |
| L-12 | No CSRF tokens | LOW | **NOT APPLICABLE** — Bearer-only API, no cookies (explicitly verified) | — |
| L-13 | `readJsonBody` swallows bad JSON | LOW | REPORTED (produces a field-specific 400) | — |
| L-14 | No `assert` invariants | LOW | REPORTED (idempotency guards verified by tests instead) | `backend/test/payment_invariants_test.dart` |
| L-15 | COD "transaction id" is server-generated | LOW | FIXED — now documented as a *settlement reference*, no `TXN…` invented | `payment_service.dart:487-537` |
| L-16 | No structured logging | LOW | REPORTED ONLY | — |
| L-17 | `is_active` not re-checked per request | LOW | MITIGATED — access tokens now expire (`exp` is enforced) | `auth_middleware.dart:78-81` |
| L-18 | Phone numbers in cleartext | LOW | REPORTED ONLY (product requirement) | — |
| L-19 | Backend lockfile ignored | LOW | **FIXED** | `backend/.gitignore:1-8` |

---

## 2. F1 — `POST /api/payments/upi/confirm` can no longer produce a paid booking (C-01)

### Before

`confirmUpi` accepted the client's word as proof. It invented a `TXN…` id when the client sent none, and `INSERT`ed a **brand-new `SUCCESS` payment row** when no attempt existed. Because earnings were derived from `paymentStatus ∈ {SUCCESS, COD_CONFIRMED}`, one authenticated POST with `{"bookingId": "<own booking>"}` marked a free booking as fully paid and confirmed.

### After — `backend/lib/services/payment_service.dart`

1. **A `PENDING` attempt must already exist.** `_liveUpiAttempt()` (`:337-354`) selects the live `PENDING` UPI row for the booking. If there is none, `confirmUpi` throws `ApiError.conflict` (`:246-250`) — HTTP **409**, and nothing is inserted.
2. **Never `SUCCESS`.** The `UPDATE` at `:272-289` is guarded by `AND payment_status = 'PENDING'` and writes only `payment_status = 'UPI_PENDING_VERIFICATION'`. `paid_at` is never set.
3. **The booking status is untouched** (`:301-315`): only `payment_method`, `payment_status` and `payment_reference` change. An unverified payment therefore **does not occupy the slot**, exactly like `COD_PENDING`.
4. **No fabricated transaction id.** `transaction_id = COALESCE(@txn, transaction_id)` where `@txn` is the caller's value **or NULL**. `_transactionId()` was **deleted outright** from the codebase.
5. **The response says so explicitly.** `_verificationBlock()` (`:324-331`) returns `verified:false`, `requiresOwnerSettlement:true`, `countsAsEarnings:false`, `holdsSlot:false` and the honest `kUpiUnverifiedMessage`.
6. **HTTP 202**, not 200 — `routes/payment_routes.dart:80-89`. A 200 would invite a client to render "paid".

The new state is declared in `backend/lib/models/booking.dart:79-113`:
`upiPendingVerification` is in `awaiting` and **not** in `paid`; `occupyingStatusList` does not contain it.

### The only path to `SUCCESS` — `PUT /api/payments/{bookingId}/upi/settle`

`routes/payment_routes.dart:141-148` → `requireUserIdOfRole(req, allowedRoles: ['owner'])` (so a `USER` JWT gets **403**) → `PaymentService.settleUpi` (`:564-616`) → `BookingService.settleUpi`, which **re-checks `bookings.owner_id` against the JWT id**. It only transitions a booking whose payment is `UPI_PENDING_VERIFICATION`, and it is idempotent, so earnings are counted exactly once.

This is the exact structural counterpart of COD: *the party who can see the money is the party who attests to it*.

### Documented limitation (required by the brief)

> A `upi://pay` intent is a **one-way, unsigned hand-off**. The UPI app tells the *user's phone* what happened; it never signs anything and never contacts this backend. Therefore this backend **cannot cryptographically verify** a UPI payment. It records a *claim* and requires the parking owner to settle it, exactly as it already required the owner to confirm cash. The real fix is a PSP webhook (`collect.request` / `payment.captured`) with signature verification; until that is integrated, UPI settlement is **owner-verified, not instant**, and the app says so on screen.

This text is also in `payment_service.dart:11-17` (`kUpiUnverifiedMessage`) and is surfaced verbatim in the UI.

---

## 3. F2 — the legacy `POST /api/payments` fabrication path is gone

`payment_service.dart:710-724` documents what the old `create()` did:

> *the old version of this method called `confirmUpi(transactionId: _transactionId())` when the client sent no id, i.e. it fabricated a gateway reference so that a client which never opened a UPI app still ended up with a `SUCCESS` payment. It now forwards only what the client actually sent, which means a legacy client that skips the `/upi/intent` step receives `409` instead of a paid booking.*

`routes/payment_routes.dart:161-174` keeps the endpoint for older client builds and its message is now honest: **"Payment request recorded and awaiting verification."**

---

## 4. F1b/F3 — COD flow preserved exactly, plus the new migration

### COD is untouched end to end

`COD_PENDING → owner confirms cash → backend verifies owner ownership → COD_CONFIRMED → CONFIRMED → earnings increase once (idempotent)`

Verified in `payment_service.dart:481-550` and pinned by tests in `backend/test/payment_invariants_test.dart`:
`COD_PENDING ∈ awaiting`, `COD_PENDING ∉ paid`, `COD_PENDING ∉ occupyingStatusList`, `COD_CONFIRMED ∈ paid`.

The only semantic change (L-15): cash has **no gateway id**, so instead of inventing `TXN…` the server records the booking's own `PSK-…` reference as a *settlement reference* and stamps `verified_at` / `verified_by` (`:519-537`). Nothing is fabricated, and the `COD_PENDING`-only transition that guarantees single counting is unchanged.

### `backend/sql/migrations/005_security_fixes.sql` — additive, idempotent, data-safe

Header lines 3-8 state the safety contract, and it is honoured:

* **No** `DROP TABLE`, **no** `DELETE`, **no** `TRUNCATE`.
* No existing user / parking / booking / payment row is modified.
* Migrations `001`–`004` are **not** edited (verified: their mtimes are unchanged from 2026-09-24/26).
* Every statement is idempotent (`DROP CONSTRAINT IF EXISTS` + `ADD CONSTRAINT`, `ADD COLUMN IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`).

Contents: the `UPI_PENDING_VERIFICATION` value added to both CHECK constraints; `payments.verified_at/verified_by/settled_reference`; `bookings.upi_verified_at/upi_verified_by`; `password_reset_otps.attempts/last_sent_at/request_ip`; indexes on `otp_hash`, `(user_id, created_at DESC)`, a partial index for the owner's verification queue, and a partial index for live refresh tokens.

**Applied live on this machine** — proof that it is idempotent (001-004 were *not* re-run):

```
Migration already applied: 001_auth.sql
Migration already applied: 002_parking_booking.sql
Migration already applied: 003_parking_slots.sql
Migration already applied: 004_owner_upi_cod.sql
Migration applied: 005_security_fixes.sql
```

---

## 5. Two additional REAL bugs found by the new test suite

These were **not** in `AUDIT_REPORT.md`. They were introduced by the hardening work in this session and caught by the new tests before shipping; both are fixed and both are now covered.

### 5.1 `rateLimitMiddleware` threw `UnsupportedError` on the first request of every new client IP

`middleware.dart:212-213` seeded the per-key hit list with `const <DateTime>[]`, then called `removeWhere` on it. `const` lists are unmodifiable, so the very first request from an unseen key crashed instead of being served — i.e. the rate limiter I added for H-05/M-13 would have 500'd the login endpoint. Caught by `backend/test/middleware_test.dart` with:

```
Unsupported operation: Cannot remove from an unmodifiable list
package:parkshare_backend/middleware/middleware.dart 213:11  rateLimitMiddleware.<fn>.<fn>
```

Fixed at `middleware.dart:205-233`: the seed is now a growable `<DateTime>[]` (the `const Duration` is the only `const`), and the window is recomputed per request so the bucket actually slides.

### 5.2 `LocalMediaStorage.serve` returned 404 for every legitimate upload on Windows

`serve` joined the directory and the filename with a literal `/` (`'${_dir.path}/${name}'`) while the containment guard compared against `'${root}${Platform.pathSeparator}'`. On Windows that produced `C:\dir/uploads/x.png` vs `C:\dir\uploads\` → `startsWith` false → **every** stored photo 404'd. This was a self-inflicted regression of the M-03 canonicalisation fix. Both `saveBytes` and `serve` now join with `Platform.pathSeparator` (`media_storage.dart:44-89`), covered by `backend/test/upload_validation_test.dart`.

---

## 6. F4 — H-01 the server refuses to start with an insecure production config

`backend/lib/config/config.dart`

* `devJwtSecret` (`:26`) is now **only** usable while `isDevelopment`. `jwtSecret` (`:84-88`) returns `''` in production when `JWT_SECRET` is absent — no fallback to a published key.
* `validateForStartup()` (`:194-242`) returns human-readable problems and **never includes a secret value** (only names, lengths and remediation commands).
* `bin/server.dart:49-65` runs it **before** `HttpServer.bind` and calls `exit(1)`.

Rules enforced: missing `JWT_SECRET`; `JWT_SECRET == devJwtSecret`; `JWT_SECRET` shorter than 32 chars; no SMTP **and** no `ALLOW_DEV_OTP`; missing `PUBLIC_BASE_URL` in production; empty CORS allow-list in production.

### Proof: booting the real `bin/server.dart` in a directory with no `.env`

`backend/test/config_startup_validation_test.dart` copies `bin/server.dart` plus an absolute-URI package config into a temp sandbox with **no `.env`**, so the environment is the only configuration source.

```
exit 1 and no listener when JWT_SECRET is missing
  -> exit code 1
  -> "refusing to start" / "JWT_SECRET is not set."
  -> stdout contains NEITHER "attempting to bind" NOR "ParkShare API listening"

exit 1 when JWT_SECRET is still the published placeholder -> "published development placeholder"
exit 1 when JWT_SECRET is too short                      -> "too short"
ALLOW_DEV_OTP=true cannot rescue a production boot        -> "ALLOW_DEV_OTP=true for a development-only run"
a production boot with no CORS allow-list is refused      -> "CORS_ALLOWED_ORIGINS must list"
a production boot without PUBLIC_BASE_URL is refused      -> "PUBLIC_BASE_URL must be set"
a fully valid production config passes validation and reaches the DB
  -> output contains NONE of the above, and contains "refused" (died on the DB socket, DB_PORT=1)
```

Actual captured output from the missing-secret case:

```
ParkShare API: refusing to start — insecure configuration.
  APP_ENV = production
  - JWT_SECRET is not set. Add a random value of at least 32 characters to backend/.env (or the process environment).
  - No SMTP server is configured (SMTP_HOST) and ALLOW_DEV_OTP is not true, so password-reset OTPs cannot be delivered. Configure SMTP, or set ALLOW_DEV_OTP=true for a development-only run.
  - PUBLIC_BASE_URL must be set in production so uploaded photo URLs cannot be poisoned through a spoofed Host header.
  - CORS_ALLOWED_ORIGINS must list the origins allowed to call the API in production (comma separated).

Fix backend/.env (see backend/.env.example), or run with APP_ENV=development for a local run.
EXITCODE=1
```

### Proof: no silent dev fallback, and the secret is never logged

```
the boot banner lists settings, never the secret value
  -> "Config loaded: appEnv=production ... devOtp=disabled ..."
  -> stdout  does NOT contain the JWT_SECRET value
  -> stderr  does NOT contain the JWT_SECRET value
the remediation text names the variable, never its value
  -> "JWT_SECRET is too short"      (value absent from the whole output)
```

`Config.load()` (`:244-254`) prints booleans and non-sensitive settings only. This machine's real `backend/.env` is asserted to hold a real `JWT_SECRET` (≠ the published placeholder, ≥ 32 chars) — the test asserts the *fact*, never the value.

---

## 7. F5 — H-02 / H-03 / H-04 / H-05 / M-08 / M-10 the password-reset flow

### H-03 — enumeration oracle removed (`auth_service.dart:13-24`, `:309-331`)

```dart
const String kForgotPasswordResponse =
    'If an account exists for that email address, a verification code has been '
    'sent to it. Please check your inbox and your spam folder.';

const String kInvalidOtpMessage = 'Invalid or expired verification code.';
```

`forgotPassword` returns the **same object** for every caller. For an unknown address it performs `_dummyPasswordWork()` (a comparable bcrypt cost) so the response *time* does not reveal existence either. The wrong-OTP path and the unknown-email path both return `kInvalidOtpMessage`.

**Live proof on the running server — byte-identical bodies:**

```
POST /api/auth/forgot-password  (unregistered address)
{"success":true,"message":"If an account exists for that email address, a verification code has been sent to it. Please check your inbox and your spam folder.","data":{"email":"definitely-not-registered-d66e9efd@example.invalid","ttlMinutes":10,"message":"If an account exists for that email address, ..."}}

POST /api/auth/forgot-password  (an address that may be registered)
{"success":true,"message":"If an account exists for that email address, a verification code has been sent to it. Please check your inbox and your spam folder.","data":{"email":"admin@parkshare.in","ttlMinutes":10,"message":"If an account exists for that email address, ..."}}
```

`backend/test/auth_messages_test.dart` locks the wording down: 17 enumeration markers (`not found`, `no account`, `does not exist`, `unknown email`, `not registered`, `invalid email`, …) must never appear.

### H-02 — the OTP is never printed and never returned in production

`auth_service.dart:386-396` is the **only** place a reset code is ever emitted:

```dart
if (Config.allowDevOtp) {
  response['devOtp'] = otp;
  response['debugNote'] = 'ALLOW_DEV_OTP is enabled: ... Never enable this in production.';
}
```

`Config.allowDevOtp` (`config.dart:139-140`) is `!isProduction && _bool('ALLOW_DEV_OTP', false) && !smtpConfigured` — three independent conditions. There is **no `print` of the OTP anywhere in the file**.

* Backend: proven by the production-boot test (`ALLOW_DEV_OTP=true` cannot rescue a production boot) and by grepping the service for any OTP `print`.
* App: `lib/core/constants/dev_flags.dart:35` — `static bool get devOtpEnabled => kDebugMode && _allowDevOtpRequested;`. `kDebugMode` is the **primary** guard (so profile builds are also safe) and the value must additionally be supplied at build time via `--dart-define=ALLOW_DEV_OTP=true`. `showDevOtpBanner` derives from it, so the dev-OTP autofill/render code in `otp_verification_screen.dart`, `forgot_password_screen.dart` and `auth_models.dart` is unreachable in a release or profile build.

**Live proof on the running server** — the complete stdout after two `forgot-password` calls and 35 `login` calls contains **no 6-digit OTP token**; the only numeric fragments are ISO timestamps and Dart VM addresses:

```
Config loaded: appEnv=development db=127.0.0.1:5432/parkshare port=8080 smtp=disabled devOtp=enabled uploads=uploads maxBytes=8388608 corsOrigins=*
Database connection verified (127.0.0.1:5432/parkshare)
Migration already applied: 001_auth.sql ... Migration applied: 005_security_fixes.sql
ParkShare API listening on http://0.0.0.0:8080
... [ApiError] 401 / [ApiError] 429 lines ...
```

### H-04 — access tokens now expire, and fail closed

`auth_service.dart:639-655` — both tokens are minted with `iat` and `exp` (`access` = `JWT_ACCESS_EXPIRES_MINUTES`, `refresh` = `REFRESH_TOKEN_DAYS`).

`middleware/auth_middleware.dart:50-90` — `_verifyAccessToken` requires `alg == 'HS256'`, requires `type == 'access'`, and **refuses a token with no numeric `exp`** (`:78-81`) rather than treating it as infinitely valid.

`backend/test/auth_middleware_test.dart` (23 tests) covers: missing header → 401; non-Bearer scheme → 401; garbage → 401; wrong signing key → 401; **expired `exp` → 401**; **no `exp` → 401 ("expiry")**; `type: refresh` → 401; `alg: none` → 401; `RS256` → 401; no `role` → 401; valid token → 200 with `userId`/`userRole` bound into the context.

### H-05 / M-13 — rate limiting, verified live

`middleware/middleware.dart:199-238` is a per-IP fixed-window limiter; `routes/auth_routes.dart` applies **two separate budgets** — `Config.authRateLimitPerMinute` (30) for register/login and `Config.otpRateLimitPerMinute` (20) for forgot/verify/reset — so a burst of reset attempts can never lock a legitimate user out of logging in. `0` disables (development only).

The bucket key is `clientIpOf(request)` (`:246-258`), which prefers `context['remoteAddress']` — bound from the **real socket** by `bin/server.dart:139-157` (`_dispatchWithPeerAddress`, deliberately replacing `shelf_io.serve` because shelf's `Request` exposes no remote address) — then the first `X-Forwarded-For` entry, then the `Host` value as a fail-closed last resort.

**Live proof — 35 rapid `POST /api/auth/login`:**

```
  HTTP 401 x30
  HTTP 429 x5
  status       = 429
  retry-after  = 60
```

And a test asserts a caller who changes `X-Forwarded-For` between requests still hits the **same** bucket:

```
a caller-supplied X-Forwarded-For cannot mint a fresh bucket
  -> 1st request 200, 2nd request (different XFF) 429
```

### M-08 — OTP lifecycle

`auth_service.dart:502-560`: an expired OTP is **consumed** (destroyed) rather than left as a guessable target; wrong guesses increment `attempts` and destroy the row at `Config.otpMaxAttempts` (5); previous unverified OTPs are invalidated on resend; a resend inside `Config.otpResendCooldownSeconds` (60) is refused with 429. The `verified_at` marker is single-use: `resetPassword` consumes it and revokes **all** refresh tokens for that user.

### M-10 — password policy

`Config.minPasswordLength` = 8 (was 6); `AuthService._commonPasswords` (`auth_service.dart:35-50`) rejects 14 trivial-but-length-passing passwords on both register and reset.

---

## 8. F6/F7/F8/F9 — transport, uploads, ownership, randomness

### F6 (M-01, M-04, M-05, M-06)

* `corsMiddleware` (`middleware.dart:136-166`) is an **allow-list** driven by `Config.effectiveAllowedOrigins`. `*` is only ever produced in development; in production an empty list means *reflect nothing*. `Vary: Origin` is **always** sent. A non-allowed origin simply receives no CORS header, so the browser blocks it.
* `securityHeadersMiddleware` (`:174-190`) adds `x-content-type-options: nosniff`, `x-frame-options: DENY`, `referrer-policy: no-referrer`, `cross-origin-resource-policy: same-site`, `permissions-policy: geolocation=(self), camera=(self), microphone=()`.
* `errorMiddleware` (`:106-124`) prints `[Unhandled] <Type> (details withheld)` in production (`Config.verboseErrors` defaults to `!isProduction`) and always answers the client with a generic 500.
* `logRequests()` is added only when `Config.requestLoggingEnabled`, i.e. **off** in production unless `LOG_REQUESTS=true` is set explicitly.
* Middleware order in `bin/server.dart:35-44` is `cors → securityHeaders → errorMiddleware → [logRequests] → handler`, so an **error** response still carries the CORS and security headers (a browser can only *read* the error otherwise). Pinned by `backend/test/middleware_test.dart`.

**Live `/health` response headers (dev, wildcard policy):**

```
HTTP/1.1 200
access-control-allow-origin: *        <- dev only; production requires an allow-list
vary: Origin
x-content-type-options: nosniff
x-frame-options: DENY
referrer-policy: no-referrer
cross-origin-resource-policy: same-site
permissions-policy: geolocation=(self), camera=(self), microphone=()
content-type: application/json
```

### F7 (M-02, M-03)

* `sniffImageType(bytes)` (`media_storage.dart:147-180`) decides the type from the **leading bytes** — JPEG `FF D8 FF`, PNG `89 50 4E 47 0D 0A 1A 0A`, WEBP `RIFF....WEBP`. The multipart `Content-Type` is never trusted; when it is present and sane it must not *contradict* the bytes (`upload_service.dart:74-83`).
* `looksExecutable(bytes)` (`:193-238`) rejects MZ, ELF, both Mach-O magics, Java class, `%PDF`, `#!`, `PK…` (zip/.jar/.apk/.docm), and `<!DOCTYPE html` / `<html` / `<?xml` / `<svg` before anything touches the disk.
* The stored extension is **derived from the sniffed type** (`extensionForImageType`), never from user input. `kForbiddenUploadExtensions` (`:135-140`) lists 28 extensions and a test asserts the produced set and the forbidden set **do not overlap**.
* Filenames use `Random.secure()` (`:35`) — 16 CSPRNG bytes, base64url, alphanumeric only.
* Size is checked at 413 (`ApiError.payloadTooLarge`) both in the service and again in storage.
* Served files always get `nosniff` + `content-disposition: inline; filename="…"`; an unknown extension is served as `application/octet-stream` and **never guessed**.
* Traversal: only the **last path segment** is honoured and the resolved path must be inside the root with a separator boundary.
* `POST /api/uploads` is **owner-only** (`routes/upload_routes.dart:27`) — it was previously reachable by any authenticated account, which made the API an unmetered public file host.

### F8 (M-12)

`GET /api/parkings/{parkingId}` used to call `requireUserId(req)` and **discard the result**, then read `userIdOf(request)` — which is `''`, because `requireUserId` only *returns* the identity. That empty `viewerId` reached the service. Now the return value is used, and `auth_middleware.dart:96-116` documents the distinction loudly so it cannot be reintroduced.

### F9 (M-07)

`Random.secure()` for: upload filenames, OTP values, token `jti`, booking/payment references. Every one of these is security-relevant.

---

## 9. F10/F11 — Flutter and Android production configuration

### H-06 / F11 — release signing is **fail-closed**

`android/app/build.gradle.kts` reads `android/key.properties`; when it is absent **and** the requested task is a release artifact, the build aborts with instructions instead of silently falling back to the debug keystore. The check is derived from `gradle.startParameter.taskNames` (a `buildingReleaseArtifact` flag) so `flutter run`, `--debug` and `--profile` need no keystore at all.

**Proof — no keystore present:**

```
$ flutter build apk --release
Create android/key.properties (this path is git-ignored):

    storeFile=<path to your upload keystore (.jks)>
    storePassword=<keystore password>
    keyAlias=<key alias>
    keyPassword=<key password>

Generate a key with:

    keytool -genkey -v -keystore ~/parkshare-upload.jks \
        -keyalg RSA -keysize 2048 -validity 10000 -alias upload

Debug builds are unaffected: `flutter run` and
`flutter build apk --debug` need no keystore.

Verify the result afterwards: `apksigner verify --print-certs ...`

BUILD FAILED in 1s
Gradle task assembleRelease failed with exit code 1     EXITCODE=1

$ flutter build appbundle --release
  ... Create android/key.properties ... Debug builds are unaffected ...
BUILD FAILED in 1s                                       EXITCODE=1

$ flutter build apk --debug
√ Built build\app\outputs\flutter-apk\app-debug.apk      EXITCODE=0
```

**Proof — the signing path really works end to end** (verified with a *throwaway* keystore in the temp directory; all of it deleted afterwards, see §11):

```
$ flutter build apk --release --dart-define=API_BASE_URL=https://api.example.invalid
√ Built build\app\outputs\flutter-apk\app-release.apk (59.2MB)

$ apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
Signer #1 certificate DN: CN=ParkShare Build Verification, OU=Audit, O=Throwaway, L=X, ST=X, C=IN

# and the debug APK, for contrast:
Signer #1 certificate DN: C=US, O=Android, CN=Android Debug
```

The release artifact is signed by the **configured upload key**, not `CN=Android Debug`.

### M-15 / cleartext — manifest hardening

`android/app/src/main/AndroidManifest.xml`: `android:allowBackup="false"`, `android:fullBackupContent="false"`, `android:dataExtractionRules="@xml/data_extraction_rules"`, `android:usesCleartextTraffic="false"`, `android:networkSecurityConfig="@xml/network_security_config"`, with the two new XML resources in `src/main/res/xml/`.

`android/app/src/debug/AndroidManifest.xml` re-enables cleartext **only** for debug builds via `tools:replace`, so local development against a plain-HTTP backend still works while release traffic is TLS-only.

**Proof from the built APKs (`aapt2 dump xmltree`):**

```
release APK:
  package="com.example.parkshare_new"
  allowBackup=false        fullBackupContent=false      usesCleartextTraffic=false
  networkSecurityConfig=@0x7f0e0003                      dataExtractionRules=@0x7f0e0000

debug APK (contrast):
  debuggable=true          allowBackup=false            usesCleartextTraffic=true
  networkSecurityConfig=@0x7f0e0003
```

### H-08 / H-02 — no dev affordances in a release build

`lib/core/constants/api_constants.dart:40-61`: `baseUrl` **throws a `StateError`** in release mode when `API_BASE_URL` is not supplied as a `--dart-define`, instead of silently falling back to `10.0.2.2:8080`. `baseUrlOrNull` and `isHttpsBaseUrl` exist for the paths that legitimately need a nullable URL (and the latter lets a caller assert TLS).

`lib/core/constants/dev_flags.dart` (new) centralises `kDebugMode && ALLOW_DEV_OTP`, as described in §7.

### H-07 — `applicationId` is **reported, not changed**

```
package="com.example.parkshare_new"        namespace = com.example.parkshare_new
```

Changing the application id is explicitly out of scope for this engagement and would break the Play listing / any already-installed build. It is an **owner action**; see §12. The literal was nonetheless centralised in Dart (`lib/core/constants/app_identity.dart`) so there is exactly one place to change it when the owner is ready.

### C-01 / C-02 in the app

* `lib/shared/models/booking.dart` mirrors the backend: `PaymentStatus.upiPendingVerification`, `awaiting`, `isUnverified`, `isUpiUnverified`, `upiVerifiedAt`, `isUpiPendingVerification`.
* `lib/shared/utils/booking_ui.dart` renders **"Verification Pending"** with its own colour and adds `isAwaitingVerification`.
* `lib/modules/booking/providers/payment_provider.dart`: `PaymentStep.success` was **removed** and replaced by `PaymentStep.upiPendingVerification` and `PaymentStep.settled`. `confirmUpi` only reports `settled` when the **server** returns a paid booking; otherwise it stops at `upiPendingVerification`.
* `lib/modules/user/booking/upi_pending_verification_screen.dart` (**new**) explains the situation without ever saying "paid"; `AppRoutes.upiPendingVerification` is registered in `lib/app/routes.dart` / `lib/app/app.dart`. `payment_screen.dart` routes into it and its dialog copy was corrected.
* `lib/modules/owner/providers/owner_dashboard_provider.dart` now prefers the **server-computed** `GET /api/payments/owner/earnings` and only falls back to the old local sum, exposing `earningsIsAuthoritative` so the UI can say which figure it is showing. The dashboard gained a **"UPI To Verify"** stat and a provenance note.
* `lib/modules/owner/bookings/owner_booking_list_tab.dart` and `owner_booking_detail_sheet.dart` gained the **"Verify UPI"** action plus a `upiVerifiedAt` row.

---

## 10. F12 — the backend test suite (L-10)

`backend/pubspec.yaml` gained `test: ^1.25.0` and `http: ^1.2.0` as dev-dependencies (there were **no** backend tests before; `dart test` failed outright with `Could not find package 'test'`).

```
$ cd backend; dart test
+129: All tests passed!
```

| File | Tests | Covers |
|---|---|---|
| `test/config_startup_validation_test.dart` | 16 | H-01 fail-fast (7 real subprocess boots of `bin/server.dart` in a `.env`-less sandbox), H-02 "no secret in output", OTP/rate-limit defaults |
| `test/auth_middleware_test.dart` | 23 | H-04 token verification (expired / no `exp` / refresh / `alg:none` / `RS256` / wrong key / garbage), role gate 401 vs 403, M-12 `requireUserId` / `authenticateAndBind` |
| `test/middleware_test.dart` | 23 | H-05 rate limiting (per-key buckets, XFF cannot mint a bucket, `0` disables), M-13 `clientIpOf` precedence, M-01 CORS, M-04 security headers, M-05 error redaction, pipeline ordering |
| `test/upload_validation_test.dart` | 27 | M-02 magic-byte sniffing, `looksExecutable` for 8 container families, extension derivation, forbidden/allowed non-overlap, traversal, sibling-prefix directory, `nosniff`/octet-stream, 413 |
| `test/route_role_gating_test.dart` | 20 | The real `ApiRouter` through the real pipeline: 401/403 **before any DB access** for `/upi/settle`, `/cod/confirm`, `/owner/earnings`, `/uploads`; payer endpoints; error headers; `/health`; 404 |
| `test/payment_invariants_test.dart` | 14 | C-01 `UPI_PENDING_VERIFICATION ∉ paid`, `∈ awaiting`, `∉ occupying`; COD state machine; `kUpiUnverifiedMessage` never claims success; `bookingCoreJson` launder check |
| `test/auth_messages_test.dart` | 6 | H-03: 17 enumeration markers absent from both messages; conditional phrasing; the two messages are distinct |

Nothing in the suite needs a database, and no test reads or prints a `.env` value.

---

## 11. Cleanup performed

Everything used for verification that is not part of the deliverable was removed:

```
key.properties exists      : False
throwaway keystore dir     : False
release apk exists         : False
release aab exists         : False
sandbox boot dirs          : False
--- any stray keystores in the repo? ---   (none)
```

The throwaway keystore was self-signed `CN=ParkShare Build Verification`, lived only in the temp directory, and grants access to nothing. `android/key.properties`, `*.jks` and `*.keystore` are all git-ignored (`.gitignore:36-46`).

**Not deleted** (they are the user's local artefacts, and deleting them was out of scope): `build/`, `.dart_tool/`, `.idea/`, `parkshare_new.iml`, `backend_run*.log`, `build_err.txt`, `e2e_*.txt`, `run_app*.log`, `backend/audit_run*.log`, `backend/uploads/` (~130 images), `backend/.env`. They are now git-ignored so they cannot be committed accidentally.

---

## 12. Acceptance report — all 19 items

| # | Requirement | Status | Proof |
|---|---|---|---|
| 1 | Audit **before** fixes, with exact file/line refs and CRITICAL/HIGH/MEDIUM/LOW classification | ✅ | `AUDIT_REPORT.md` — 2 Critical, 8 High, 17 Medium, 19 Low, plus a per-endpoint IDOR table. Its mtime predates the first fix commit (audit 15:13, first fix 15:18). |
| 2 | Backend analyzer clean | ✅ | `cd backend; dart analyze` → `No issues found!` |
| 3 | App analyzer clean, no blanket suppression | ✅ | `flutter analyze` → `No issues found! (ran in 1.8s)`. `analysis_options.yaml` is the stock `flutter_lints` set; no new `ignore_for_file` added. |
| 4 | Focused backend security tests | ✅ | `dart test` → `+129: All tests passed!` across 7 new files (F12, §10) |
| 5 | App tests still green | ✅ | `flutter test` → `+127: All tests passed!` |
| 6 | Backend actually starts and serves | ✅ | `Migration applied: 005_security_fixes.sql`, `ParkShare API listening on http://0.0.0.0:8080`; `GET /health` → `200 {"success":true,...,"status":"ok"...}` with the full security header set |
| 7 | `/upi/confirm` is **not** treated as verified; no fabricated txn IDs; no `SUCCESS` without a pending transaction; limitation documented | ✅ | `payment_service.dart:227-331` + `routes/payment_routes.dart:80-89` (HTTP **202** + `paymentVerification{verified:false, countsAsEarnings:false, holdsSlot:false}`); `_transactionId()` deleted; 409 without a `PENDING` row; 14 invariant tests; new owner-facing `upi_pending_verification_screen.dart`; limitation stated in code, in the API message and in §2 above |
| 8 | COD flow unchanged and idempotent | ✅ | `payment_service.dart:481-550`; `COD_PENDING → COD_CONFIRMED → CONFIRMED → earnings once`; guarded by `AND payment_status = 'COD_PENDING'` so a second confirm matches no rows; 4 dedicated invariant tests |
| 9 | OTP: never returned/logged in production; dev OTP gated by explicit `ALLOW_DEV_OTP=true`; enumeration removed; expiry, single-use, attempt limit, resend cooldown, rate limiting; refresh tokens revoked after reset | ✅ | `config.dart:139-140`; `auth_service.dart:386-396`; `kForgotPasswordResponse`/`kInvalidOtpMessage`; `otpMaxAttempts=5`, `otpResendCooldownSeconds=60`, `otpTtlMinutes=10`; migration 005 `attempts`/`last_sent_at`/`request_ip` + indexes; live 30×401 then 5×429 with `retry-after: 60`; live byte-identical forgot-password bodies; no OTP in the server log |
| 10 | JWT: server fails to start if `JWT_SECRET` is missing/insecure in production; no silent dev fallback; secret never logged | ✅ | 7 real boots in `config_startup_validation_test.dart`; `bin/server.dart:49-65` exits 1 **before** `bind`; verified valid-config boot reaches the DB stage; "no secret in stdout/stderr" assertions |
| 11 | IDOR / role audit of **every** endpoint; 403 for a `USER` JWT on owner endpoints | ✅ | `AUDIT_REPORT.md` §6.5 per-endpoint table; 20 route-level tests drive the real router and assert 401 (no token) → 403 (`user`) → gate opens (`owner`) **before any DB access**; live `PUT /upi/settle`, `PUT /cod/confirm`, `GET /owner/earnings`, `POST /uploads` all 401 without a token |
| 12 | Migrations: applied ones never edited; new idempotent, data-safe `005` | ✅ | `001`–`004` mtimes unchanged; `005_security_fixes.sql` header states the contract and contains no `DROP TABLE` / `DELETE` / `TRUNCATE`; live run reported 001-004 as *already applied* and only applied 005 |
| 13 | SQL injection, file upload, CORS, secret logging | ✅ | All SQL uses `Sql.named` + bound parameters (no concatenation anywhere); uploads sniffed by magic bytes, extension derived from bytes, owner-only, 413, traversal-safe, `nosniff`; CORS is an allow-list with `Vary: Origin` and `*` only in development; secret never logged (proven above) |
| 14 | Android production config; `applicationId` reported only | ✅ | Fail-closed signing (§9); `allowBackup=false`, `fullBackupContent=false`, `usesCleartextTraffic=false`, `networkSecurityConfig`, `dataExtractionRules` all confirmed in the built APK; `applicationId` unchanged and reported |
| 15 | Google Sign-In reported **MISSING** | ✅ | `AUDIT_REPORT.md` L-03: not a dependency, no UI, no backend route. Login is email+password only. |
| 16 | Flutter secure storage | ✅ | `flutter_secure_storage` used for tokens; dev reset helper moved behind `AppIdentity`/debug gating. (`flutter_secure_storage` 9.2.4 has a newer major available — see L-09; no advisory-driven bump.) |
| 17 | Map tiles / User-Agent; provider must not change | ✅ | Esri World Imagery with attribution **unchanged**; the UA is now a stable, identifying string sourced from `lib/core/constants/app_identity.dart` instead of the placeholder package name |
| 18 | Dependencies reviewed | ✅ | `flutter pub outdated` → 39 packages with newer versions, all blocked by current constraints; `dart pub outdated` → 3. **No security-advisory-driven bump is available**, so no forced major upgrade was made. |
| 19 | Release builds | ✅ | `apk --release` and `appbundle --release` both **fail closed** with actionable instructions when no keystore exists; both **succeed** when one does (verified with a throwaway key, then deleted); release APK confirmed signed by the configured key, not `CN=Android Debug` |

### Command transcript (final state)

```
cd backend  && dart analyze   ->  No issues found!
cd backend  && dart test      ->  +129: All tests passed!
flutter analyze               ->  No issues found! (ran in 1.8s)
flutter test                  ->  +127: All tests passed!
flutter devices               ->  Windows (desktop), Chrome (web), Edge (web)   [no Android device attached]
flutter build apk --debug     ->  Built build\app\outputs\flutter-apk\app-debug.apk
flutter build apk --release        ->  BUILD FAILED (exit 1)  [no keystore: fail-closed, H-06]
flutter build appbundle --release  ->  BUILD FAILED (exit 1)  [no keystore: fail-closed, H-06]
dart run bin/server.dart      ->  ParkShare API listening on http://0.0.0.0:8080
GET http://localhost:8080/health ->  200 OK
```

---

## 13. Residual risk and required owner actions

**Not fixable in code by this engagement — needs the owner:**

1. **H-07 — change `applicationId`/`namespace`** away from `com.example.parkshare_new` before any Play Store submission. The literal now lives in exactly one place per language (`android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `lib/core/constants/app_identity.dart`), so this is a three-line change.
2. **H-06 — create a real upload keystore** and put `android/key.properties` on the build machine. Until then release builds refuse to run, which is the intended safe state. Back the keystore up; losing it means losing the ability to update the listing.
3. **M-09 — rotate `JWT_SECRET` and `DB_PASSWORD`** in `backend/.env`, and keep `.env` out of version control / backups. Values are never printed by the app, the server or the tests.
4. **M-16 — terminate TLS and set `PUBLIC_BASE_URL`.** The backend now *refuses* a production boot without it, precisely because deriving the base from a request's `Host` header lets a caller with a token persist attacker-chosen photo URLs.
5. **Configure SMTP** in production, or password reset is unusable (and the server will refuse to start).

**Known, accepted limitations:**

* **UPI settlement is owner-verified, not instant.** Documented in §2. Integrate a PSP webhook before marketing UPI as instantaneous.
* **A pending (unverified) UPI payment no longer reserves the slot.** Intentional and consistent with `COD_PENDING`: unverified money must not consume inventory. This is a visible change in availability behaviour and is called out in `AUDIT_REPORT.md` §9.
* **The rate limiter is in-process and fixed-window.** Correct for a single node. A multi-instance deployment **must** move it to a shared store (Redis) or the effective limit becomes N × the configured value. Documented in the middleware's doc comment.
* **`clientIpOf` trusts `X-Forwarded-For` only when no socket address is present.** Behind a TLS terminator that forwards a client-supplied header unchanged, prefer the proxy's own address.
* **M-14 — refresh-token reuse detection is partial.** Tokens rotate, are stored hashed, and are revoked in bulk on logout and on password reset, but a *replayed* refresh token is not yet treated as theft. Access tokens are now time-bounded (`exp` enforced), which caps the exposure window; adding a per-token family/jti revocation list is the follow-up.
* **M-17 — the payer's payment screen still needs the owner's UPI id and phone** to complete a payment and to coordinate cash. The exposure is now scoped to that purpose only; a separate "pay by link" flow would remove it entirely.
* **Tooling / maintenance items** deliberately left alone: L-07 URI encoding, L-08 dead branches, L-16 structured logging, L-18 phone-number protection. None is an exploitable path today.

---

## 14. Final re-verification pass (after the `.gitignore` edits)

Everything below was re-run once more on the final working tree, so the numbers in §12 describe the tree as delivered.

```
cd backend && dart analyze    ->  No issues found!
cd backend && dart test       ->  +129: All tests passed!
flutter analyze               ->  No issues found!
flutter test                  ->  +127: All tests passed!

# boot with the real .env (ALLOW_DEV_OTP unset) -> correctly FAILS CLOSED, exit 1
#   "ParkShare API: refusing to start - insecure configuration."
#   "No SMTP server is configured (SMTP_HOST) and ALLOW_DEV_OTP is not true..."
$env:ALLOW_DEV_OTP='true'; dart run bin/server.dart
  -> Migration applied: 005_security_fixes.sql
  -> ParkShare API listening on http://0.0.0.0:8080

GET /health -> 200 {"success":true,...,"status":"ok"}
   nosniff · DENY · no-referrer · same-site · permissions-policy · vary: Origin

Bearer <garbage> -> PUT /api/payments/1/upi/settle      401
                     PUT /api/payments/1/cod/confirm     401
                     GET /api/payments/owner/earnings   401
                     POST /api/uploads                  401

PORT 8080 FREE after shutdown; no stray key.properties / *.jks / *.keystore
```

One cosmetic fix came out of this pass: the fail-closed startup banner in `backend/bin/server.dart:52` contained an em dash, which rendered as `?` on a Windows console (stderr encoding is platform dependent). It is now ASCII-only, so the operator actually sees the message that stops the server. Every other non-ASCII character in `backend/lib` and `backend/bin` is inside a `//` or `///` comment and never reaches a response or the terminal.

This pass also re-confirms the intended local-dev contract: **`ALLOW_DEV_OTP` must be `true` for a local run**, because `.env` has no SMTP server and the server refuses to boot with password reset undeliverable. That refusal is the H-01 control working, not a regression.

---

*End of `AUDIT_FIX_LOG.md`. See `AUDIT_REPORT.md` for the pre-fix findings and the full per-endpoint authorisation table.*
