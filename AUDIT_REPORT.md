# ParkShare — Production-Readiness Security Audit Report

**Project:** ParkShare (`parkshare_new` Flutter app + `parkshare_backend` Dart/Shelf API + PostgreSQL)
**Version audited:** `pubspec.yaml` 1.0.0+1 / backend 0.1.0
**Toolchain:** Flutter 3.47.1 / Dart 3.13.1 / PostgreSQL 17 (service `postgresql-x64-17`, running)
**Audit date:** 2026-10-05
**Scope:** full source review of `lib/` (Flutter), `backend/lib` + `backend/bin` (API), `backend/sql/migrations` (schema), `android/` (production config), plus analyzer/tests/dependency/build verification.
**Out of scope (reported, not changed):** live infrastructure, payment-gateway PSP accounts, App Store / Play Store console configuration.

---

## 0. Executive summary

The application is competently built: all SQL is parameterised, password hashing is bcrypt, refresh tokens are stored hashed and rotated, JWT verification correctly pins HS256 (no `alg:none` / algorithm-confusion), booking/parking/vehicle/inbox ownership checks are present on nearly every endpoint, slot double-booking is prevented by a PostgreSQL `EXCLUDE USING gist` constraint, and the Flutter analyzer plus 127 unit tests are green.

However, the audit found **one Critical defect in the payment domain and two High-severity authentication defects** that together allow complete bypass of the money flow and account takeover of arbitrary accounts when the service is deployed as-is:

* **C-01** — `POST /api/payments/upi/confirm` accepts the *client's word* that a payment succeeded, **fabricates a transaction ID when the client omits one**, and **INSERTs a brand-new `SUCCESS` payment row when no pending attempt exists**. The booking is then flipped to `CONFIRMED`. Because owner earnings are derived from `paymentStatus ∈ {SUCCESS, COD_CONFIRMED}`, any authenticated vehicle user can mark their own booking as fully paid with one HTTP call and zero rupees. This is not "unverified"; it is a total payment-bypass primitive.
* **H-01** — the JWT signing secret silently falls back to the literal string `dev-only-insecure-secret-change-me`, and the server never refuses to start in production. Anyone who has read this repository can mint a valid access token for **any user id and any role**.
* **H-02** — the password-reset OTP is `print()`ed to stdout *and* returned to the client in a `devOtp` JSON field whenever SMTP is unconfigured, then auto-filled and rendered on-screen by the Flutter OTP screen. A public deployment without SMTP hands over account takeover for every account whose email is known.
* **H-04** — access tokens carry **no `exp`/`iat` claims at all** (see §4.3), so `JWT_ACCESS_EXPIRES_MINUTES` is a lie: a stolen access token is valid forever.

In total: **2 Critical, 8 High, 17 Medium, 19 Low**.

The remediation plan (applied in `AUDIT_FIX_LOG.md`) removes the payment-bypass primitive while **preserving the product's cash-on-delivery flow exactly as specified** (`COD_PENDING → owner confirms → COD_CONFIRMED → CONFIRMED → earnings count once, idempotent`) and introduces a non-verified UPI state (`UPI_PENDING_VERIFICATION`) rather than pretending a UPI payment was verified.

---

## 1. Verification performed (commands + results, baseline before any change)

| # | Command | Result |
|---|---|---|
| V1 | `flutter --version` | Flutter 3.47.1 · Dart 3.13.1 |
| V2 | `cd backend; dart pub get; dart analyze` | **No issues found!** (3 packages have newer incompatible versions) |
| V3 | `flutter pub get; flutter analyze` | **No issues found!** (ran in 1.5s; 39 packages have newer incompatible versions) |
| V4 | `flutter test` | **All tests passed!** (127 tests) |
| V5 | `cd backend; dart test` | **FAILED** — `Could not find package 'test' or file 'test:test'`. Backend has **zero** unit/integration tests and no `test` dev-dependency. |
| V6 | `Get-Service *postgres*` | `postgresql-x64-17` → **Running** |
| V7 | `Get-NetTCPConnection -LocalPort 8080` | no listener (port free) |
| V8 | `git -C C:\Parkshare_new status` | `fatal: not a git repository` → **git-history secret scanning is NOT APPLICABLE**. No VCS history exists to leak `.env`. |
| V9 | `backend/.env` key presence check | `DB_PASSWORD` **FOUND** (non-empty), `JWT_SECRET` **FOUND** (non-empty), `SMTP_HOST`/`SMTP_USER`/`SMTP_PASSWORD` **NOT SET**. Values are deliberately **not** printed or copied anywhere. |
| V10 | `dart pub outdated` / `flutter pub outdated` | 3 backend + 39 Flutter packages have newer versions, all blocked by current constraints (no security-advisory-driven bumps available). |
| V11 | Grep for `google_sign_in` in `pubspec.yaml` | **MISSING** — the only hit for Google Sign-In anywhere is a stale build-cache artifact. The feature is not implemented. |

**Analyser baseline:** both `dart analyze` (backend) and `flutter analyze` (root) report **No issues found**. `analysis_options.yaml` is the stock `flutter_lints`/`lints` set — no `ignore_for_file`, no blanket suppression (verified by reading every `// ignore` in the tree).

---

## 2. Critical findings

### C-01 — UPI confirmation is client-asserted; transaction IDs are fabricated; `SUCCESS` rows are manufactured
**Severity: CRITICAL** · **Class: Broken access control / business-logic (payment integrity)**

**Files / lines**
* `backend/lib/services/payment_service.dart:181-288` — `confirmUpi()`
  * `:197-199` — fabricated transaction ID
  * `:230-255` — fabricated `SUCCESS` payment row when no `PENDING` row exists
  * `:256-273` — booking flipped to `CONFIRMED`
* `backend/lib/services/payment_service.dart:470-497` — legacy `create()`; `:483-487` calls `confirmUpi` with `transactionId: _transactionId()` when the client sends none
* `backend/lib/routes/payment_routes.dart:49-67` — `POST /api/payments/upi/confirm` passes `body['transactionId']` straight through; `:117-127` — legacy `POST /api/payments`
* `backend/lib/services/payment_service.dart:606-613` — `_transactionId()` generates a random `TXN…` string locally
* `backend/lib/models/booking.dart:81` — `PaymentStatus.paid = {success, codConfirmed}`
* `lib/modules/owner/providers/owner_dashboard_provider.dart:73-81` — `totalEarnings` sums `amount` for every booking whose `paymentStatus` is in `PaymentStatus.paid`

**Problem**
```dart
final txn = (transactionId?.trim().isNotEmpty ?? false)
    ? transactionId!.trim()
    : _transactionId();                       // ← payment_service.dart:197-199
...
if (updated.isEmpty) {
  // No live PENDING attempt: create the confirmed row directly so a
  // client that skipped the intent step still ends up recorded.
  await tx.execute(Sql.named('''
    INSERT INTO payments (... 'SUCCESS', @txn ...) ...
  '''));                                     // ← payment_service.dart:230-255
}
```
The endpoint has **no trusted payment evidence of any kind**. It never called a PSP, never verified a signature, never checked the payee, and never required that the previous `/upi/intent` step happened. The comment in the source states the intent explicitly — a client that *skips the intent step still ends up recorded* as a successful payment.

**Impact**
1. **Free parking / zero-revenue bookings.** Any authenticated vehicle user calls `POST /api/payments/upi/confirm {"bookingId":"<own booking>"}` (no `transactionId` needed) → `SUCCESS` payment + `CONFIRMED` booking. Slot is consumed, owner sees the booking, and it is counted as earnings.
2. **Forged receipts.** A client can supply an arbitrary `transactionId` string (any text up to the column length) that is stored verbatim and surfaced to the owner as `payment.transactionId` / `upiTransactionId`. Owners reconciling against their bank statement have no way to detect the forgery.
3. **Audit-trail poisoning.** `payment_reference` can be overwritten (`reference = COALESCE(reference, @ref)` never overwrites, but the INSERT path lets the client choose it on a fresh row), and `raw_response` stores attacker-controlled JSON.
4. **Server-side data inconsistency.** `payments` can contain `SUCCESS` rows with no matching `PENDING` predecessor, so no first-party record of the intent that produced the money movement exists.

**Reproduction** (own booking, valid user JWT, no `transactionId`)
```
POST /api/payments/upi/confirm  {"bookingId":"<my booking id>"}
→ 200 {"success":true,"message":"Payment successful.","data":{... "status":"CONFIRMED",
        "paymentStatus":"SUCCESS","upiTransactionId":"TXN7QF2M9XKD1"}}
```
No UPI app is ever opened; no money moves; the owner dashboard now shows the amount in **Total Earnings**.

**Required fix**
* Require an existing `PENDING` UPI payment row created by `POST /upi/intent`. Refuse (`409`) when there is none — never insert a `SUCCESS` row.
* **Never** fabricate a transaction ID. If the client supplies none, store `NULL` and require the owner's manual settlement instead.
* Because a bare `upi://` intent gives the server **no cryptographic proof of payment**, the result must be recorded as a *non-verified* state — `UPI_PENDING_VERIFICATION` — and the booking must **not** become `CONFIRMED`/earnings-earning until an owner/admin settles it. The response message must say the payment is *not yet verified*, not "Payment successful."
* Document the residual limitation: without a PSP webhook or a signed collect-request callback the backend **cannot** verify UPI settlement on its own.
* Remove the legacy `create()` fabrication path.

---

### C-02 — Owner earnings are derived from a client-writable status with no server-side ledger
**Severity: CRITICAL (impact amplifier of C-01)** · **Class: Business-logic / data integrity**

**Files / lines**
* `lib/modules/owner/providers/owner_dashboard_provider.dart:69-85` — `totalEarnings`, `paidBookingsCount`
* `lib/shared/models/booking.dart:58`, `lib/core/constants/legal_content.dart:182-194` — the UI/legal copy asserts "a booking is not treated as paid … until they [the owner] confirm"

**Problem**
`totalEarnings` is computed **entirely on the client** from the `paymentStatus` field of each booking the server returns. There is no server-side aggregate, no double-entry ledger, and no settlement record. Combined with C-01, the number an owner sees for "money I have earned" is fully attacker-controlled for UPI.

**Impact**
Financial misreporting to owners; loss of trust; no way to reconcile against a bank statement; refunds (see `legal_content.dart:203-211`) have no authoritative source.

**Required fix**
Owner-visible money must be gated on a **server-verified** state only (owner-confirmed COD, or PSP-confirmed UPI). Until then the UI must not present `UPI_PENDING_VERIFICATION` as earnings.

---

## 3. High findings

### H-01 — JWT signing secret has a hard-coded dev fallback and no production guard
**Severity: HIGH** · **File:** `backend/lib/config/config.dart:24-25`
```dart
static String get jwtSecret =>
    _env['JWT_SECRET'] ?? 'dev-only-insecure-secret-change-me';
```
* No environment/NODE_ENV switch exists anywhere in the backend (verified: no `environment`, `isProduction`, or `NODE_ENV` reference).
* `backend/bin/server.dart:19-28` never validates configuration; `Config.load()` (`config.dart:56-63`) only `print`s a summary and **does not** print any secret (that part is correct).
* Consequence: with `.env` missing or `JWT_SECRET` unset, the server starts and signs with a secret that is published in this repository. Anyone can construct `{sub:"<any user uuid>", role:"owner", type:"access", jti:"x"}` signed with `dev-only-insecure-secret-change-me` and obtain full administrative access.
* Even when `.env` **is** present (it is, in this package — see M-09), the fallback remains armed: a deploy that forgets to mount the env file silently downgrades to the known key with no warning.

**Fix:** fail fast. In production, if `JWT_SECRET` is absent, shorter than 32 chars, or equal to the dev literal → refuse to start (`exit(1)`) with a remediation message. Never log the secret. Keep the dev fallback only when `APP_ENV=development`.

### H-02 — Password-reset OTP is printed to the console and returned to the client
**Severity: HIGH** · **Class: Sensitive data exposure / account takeover**

**Files / lines**
* `backend/lib/services/auth_service.dart:276-285`
  ```dart
  print('[OTP] For ${user.email}: $otp (expires in ${ttl.inMinutes} min)');
  ...
  if (!Config.smtpConfigured) { result['devOtp'] = otp; }
  ```
* `backend/lib/config/config.dart:41` — `smtpConfigured` is `false` when `SMTP_HOST` is empty (**it is empty in this deployment**, V9)
* `lib/modules/auth/models/auth_models.dart:38,43,50` — parses `devOtp`
* `lib/modules/auth/screens/forgot_password_screen.dart:49` — forwards it in route args
* `lib/modules/auth/screens/otp_verification_screen.dart:33,42-48` — auto-fills the 6 boxes
* `lib/modules/auth/screens/otp_verification_screen.dart:157-174` — **renders the OTP on screen**: `'Development mode: OTP auto-filled ($_devOtp)'`
* `lib/app/routes.dart:40,43` — `RouteArgs.devOtp`

**Impact**
On any deployment where SMTP is not configured (including a production deploy that forgot `SMTP_HOST`), the OTP appears (a) in server stdout/logs, (b) in the HTTP response body, and (c) rendered on the user's phone. Anyone with log access, proxy access, or shoulder-surfing resets the account and takes it over.

**Fix:** production must never log or return the OTP. Gate the dev behaviour behind an explicit `ALLOW_DEV_OTP=true` **and** `APP_ENV=development`; the Flutter side must gate auto-fill/rendering behind `kDebugMode` **and** an explicit `ALLOW_DEV_OTP` dart-define.

### H-03 — Account enumeration via differentiated forgot-password and verify-OTP responses
**Severity: HIGH** · **Class: Information disclosure**

**Files / lines**
* `backend/lib/services/auth_service.dart:253` — `throw ApiError.notFound('No account found for this email address.')` inside `forgotPassword`
* `backend/lib/services/auth_service.dart:398-400` — same message inside `_requireUserWithValidOtp`

**Impact**
`404` for unknown emails vs `200` for known ones enumerates the entire user base (names + emails) for spam/phishing/credential stuffing. `register()` (`:95-97`) additionally returns `409 An account with this email already exists`, reinforcing it.

**Fix:** identical response body/status for known and unknown emails. Also fix the ordering in `_requireUserWithValidOtp` so the OTP lookup is performed unconditionally (constant-ish work) rather than short-circuiting on user existence.

### H-04 — Access tokens contain no `exp`/`iat` claims: they never expire
**Severity: HIGH** · **Class: Broken authentication / session management**

**File:** `backend/lib/services/auth_service.dart:431-451`
```dart
final accessExpires = now.add(Duration(minutes: Config.accessExpiryMinutes));
final accessToken = JWT({
  'sub': user.id, 'role': user.role, 'type': 'access', 'jti': jti,
}).sign(SecretKey(Config.jwtSecret), algorithm: JWTAlgorithm.HS256);
```
`accessExpires` is computed and returned in the response body (`TokenPair.accessExpiresAt`) but **never placed in the token**. `dart_jsonwebtoken` does not add `exp` automatically. `backend/lib/middleware/auth_middleware.dart:43-77` therefore verifies the signature and `type` but can never check expiry.

**Impact**
A leaked access token (log file, proxy, device backup, screenshot of the app's storage) is valid **forever**. `JWT_ACCESS_EXPIRES_MINUTES=60` is documented behaviour that does not exist. Combined with H-01 this compounds: rotating the secret is the only mitigation, and after rotation every user is hard-logged-out with no graceful expiry.

**Fix:** add `exp` (and `iat`) claims to both tokens using `Config.accessExpiryMinutes` / `Config.refreshTokenDays`; `JWT.verify(..., expiry: ...)` in the middleware then enforces it.

### H-05 — OTP brute force: no attempt limit, no resend cooldown, no rate limiting
**Severity: HIGH** · **Class: Broken authentication**

**Files / lines**
* `backend/lib/services/auth_service.dart:246-286` — `forgotPassword` (no cooldown, no per-IP/user throttle)
* `backend/lib/services/auth_service.dart:291-302` — `verifyResetOtp` (no attempt counter)
* `backend/lib/services/auth_service.dart:401-427` — `_requireUserWithValidOtp` (unbounded `SELECT … WHERE otp_hash = @hash`)
* `backend/sql/migrations/001_auth.sql:25-32` — `password_reset_otps` has **no** `attempts`/`last_sent_at` column and **no** index on `otp_hash`
* `backend/lib/services/auth_service.dart:129-156` — `login` has no throttling / lockout at all

**Impact**
A 6-digit OTP (10⁶ space) is brute-forceable: the endpoint is unauthenticated, unthrottled, un-locked, and returns a distinguishable error for "expired" vs "invalid". Combined with H-03 the attacker also learns the account exists. Login credential stuffing is equally unthrottled.

**Fix:** add `attempts` and `last_sent_at` columns; enforce a per-OTP attempt cap (e.g. 5) that invalidates the OTP; enforce a resend cooldown (e.g. 60 s); add in-process rate limiting on the auth routes; index `otp_hash`.

### H-06 — Android release build is signed with the debug keystore
**Severity: HIGH** · **Class: Release engineering / supply chain**

**File:** `android/app/build.gradle.kts:32-38`
```kotlin
buildTypes {
    release {
        // TODO: Add your own signing config for the release build.
        signingConfig = signingConfigs.getByName("debug")
    }
}
```
**Impact**
* The debug keystore is a well-known, publicly derivable key (its private key ships inside every Android SDK). Anyone can produce an APK with the **same signature and versionCode**, and it will be accepted as an update over the legitimately installed app on devices that allow it.
* `debug.keystore` is not in this repo, but its identity is fixed and forgeable — this is not a secret in any meaningful sense.
* `flutter build appbundle` / Play upload will be rejected or, if bypassed, ship an app that can never be updated and whose signature proves nothing.

**Status: PRODUCTION SIGNING NOT CONFIGURED.** Fix = wire `key.properties` + `signingConfigs.create("release")` and *fail the release build* when the keystore is absent (no silent fallback to debug). Per instructions the current value is reported, not silently replaced.

### H-07 — `applicationId` / `namespace` is `com.example.parkshare_new`
**Severity: HIGH** · **File:** `android/app/build.gradle.kts:8,19`
```kotlin
namespace = "com.example.parkshare_new"
applicationId = "com.example.parkshare_new"
```
Mirrored in `lib/core/constants/map_tiles.dart:40` (`userAgentPackageName`), `lib/core/storage/dev_reset_helper.dart:26-28`, `lib/core/services/upi_app_probe.dart:109`, `integration_test/e2e_flow_test.dart:37,39`.

**Impact**
`com.example.*` is reserved for samples and **cannot be published to Google Play** (blocked by Play Console policy). Anyone can claim the id once it is retired. The same literal appears in the Esri tile User-Agent (`map_tiles.dart:40`) — Esri's tile terms require an identifying User-Agent; `com.example.parkshare_new` is not an identifying app identity, which is a **tile-terms compliance** issue for production traffic.

**Status: REPORTED — NOT CHANGED** (per instruction not to randomly change the applicationId; changing it is an app-identity decision that invalidates installs, deep links and the Play listing).

### H-08 — Release build can leak the OTP dev-OTP UI and dev API base URL
**Severity: HIGH** · **Class: Insecure default configuration**

**Files / lines**
* `lib/core/constants/api_constants.dart:24-38` — with no `--dart-define`, a **release** build silently points at `http://10.0.2.2:8080` (Android) / `http://localhost:8080` (all other platforms) — cleartext HTTP, emulator loopback.
* `lib/modules/auth/screens/otp_verification_screen.dart:42-48,157-174` — dev-OTP auto-fill + on-screen rendering are **not** guarded by `kDebugMode`, so they are compiled into release builds.
* `lib/core/services/upi_app_probe.dart`, `lib/core/storage/dev_reset_helper.dart` — developer tooling shipped in the app bundle.

**Fix:** assert `https://` + explicit `--dart-define=API_BASE_URL` in release; gate all dev affordances behind `kDebugMode`; guard dev tools with `kDebugMode` so they are tree-shaken from release.

---

## 4. Medium findings

### 4.1 M-01 — CORS allows every origin unconditionally
`backend/lib/middleware/middleware.dart:99-116` always sends `Access-Control-Allow-Origin: *` with `Access-Control-Allow-Headers: … Authorization`. Not dangerous for a pure Bearer API (no cookies ⇒ no credentialed cross-origin risk, and `*` is incompatible with `credentials: include`), but it lets **any** web page drive the API from a victim's browser and exfiltrate whatever its own JS can read. Fix: allow-list `CORS_ALLOWED_ORIGINS` from config; `*` only when `APP_ENV=development`.

### 4.2 M-02 — Upload validation trusts the client's `Content-Type`; no magic-byte check
`backend/lib/services/upload_service.dart:41-49` validates **only** the multipart part header (`data.part.headers['content-type']`), which the client fully controls. `backend/lib/storage/media_storage.dart:36-49` writes the bytes with an extension derived from that header. There is **no** magic-byte sniffing, **no** image decode, and **no** explicit rejection list (`.php`, `.html`, `.svg`, `.js`, `.exe`, …). `POST /api/uploads` (`backend/lib/routes/upload_routes.dart:20-26`) is `authMiddleware()` with **no role restriction**, so a plain `user` JWT can upload unlimited files — an unauthenticated-cost storage-abuse and malware-hosting vector (the files are then served publicly at `/uploads/<name>`). Fix: sniff magic bytes (`FFD8FF`/`89504E47`/`52494646…WEBP`), derive the extension from the sniffed type, reject executables/scripts, cap total uploads, and restrict the route to `allowedRoles: ['owner']`.

### 4.3 M-03 — Path-traversal guard is a string `startsWith`, and stored URLs are built from the `Host` header
* `backend/lib/storage/media_storage.dart:52-60` — `serve()` takes `relative.split('/').last` (safe against `/../`) but then validates with `resolved.startsWith(uploadRoot)`, a classic prefix bug (`C:\app\uploads-evil` starts with `C:\app\uploads`). Impact is currently low because the filename is always server-generated, but the guard is wrong and should compare canonicalised paths with a separator.
* `backend/lib/storage/media_storage.dart:95-100` — `publicUrlFor()` falls back to `http://${request.requestedUri.host}:${port}` when `PUBLIC_BASE_URL` is unset. A caller who controls the `Host` header (valid JWT + a malicious `Host`) persists attacker-chosen URLs into `parking_photos`. Fix: require `PUBLIC_BASE_URL` in production.

### 4.4 M-04 — No security response headers
`backend/bin/server.dart:24-28` sets only `logRequests` + `cors` + `error`. Missing `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy`, `Content-Security-Policy`, `Strict-Transport-Security`, `Permissions-Policy`. `nosniff` matters here because `media_storage.dart:71-83` defaults every unknown extension to `image/jpeg`.

### 4.5 M-05 — `errorMiddleware` prints full exception + stack trace to stdout
`backend/lib/middleware/middleware.dart:90-92` — `print('[Unhandled] $e\n$st')`. Any unhandled exception (including ones carrying SQL fragments) lands in logs. Fix: log a correlation id + type only in production; never the stack.

### 4.6 M-06 — `logRequests()` is unconditionally enabled
`backend/bin/server.dart:25`. Shelf's request logger writes one line per request; combined with H-02's `print('[OTP] …')` this is an audit trail of OTP delivery. Fix: keep for dev, gate/quiet in production (or replace with a redacting logger).

### 4.7 M-07 — Non-cryptographic `Random()` for security-relevant identifiers
* `backend/lib/services/payment_service.dart:28,596-613` — booking reference `PSK-…` and transaction-ID fallback `TXN…` use `Random()`.
* `backend/lib/storage/media_storage.dart:33,85-88` — upload filenames use `Random()`.

Predictable upload filenames are enumerable; predictable references are guessable. Note `backend/lib/services/auth_service.dart:22` correctly uses `Random.secure()` — the two are inconsistent. Fix: `Random.secure()` (or `dart:math`'s CSPRNG) everywhere an identifier is unguessable-by-design.

### 4.8 M-08 — OTP "verified" state can be reused across an arbitrarily long window
`backend/lib/services/auth_service.dart:291-302` sets `verified_at`; `:421-425` only re-checks `expires_at`, so a verified OTP remains usable until its original expiry. Minor, but tightening to a short verify→reset window (e.g. 10 min from `verified_at`) is standard.

### 4.9 M-09 — `.env` with live secrets is present inside the delivered package
`backend/.env` exists and contains **non-empty** `DB_PASSWORD` and `JWT_SECRET` (values not printed). `backend/.gitignore:8` excludes `.env`, **but**:
* the repository is not a git repository at all (V8), so nothing actually enforces the exclusion;
* the root `.gitignore` (48 lines) contains **no** `backend/` patterns at all;
* the `.env` file is physically inside the package that was handed over.

**Required actions:** exclude `backend/.env` from any archive/repo; **rotate** `JWT_SECRET` and the DB password (they must be considered compromised); keep `backend/.env.example` placeholders. See also L-01.

### 4.10 M-10 — Password policy is a 6-character minimum, no complexity, no lockout
`backend/lib/services/auth_service.dart:55-57` and `:312-314` — `password.length < 6`. With no login throttling (H-05) this is brute-forceable. Fix: raise the minimum (≥ 8–10), reject trivially common values, and add throttling/lockout.

### 4.11 M-11 — `password_reset_otps` has no index on `otp_hash` and no cleanup job
`backend/sql/migrations/001_auth.sql:25-36` — every OTP verification does a full scan of the table; rows are only deleted on reset (`auth_service.dart:330`) or superseded (`:263`). Unbounded growth on a public endpoint. Fix: index `otp_hash`, purge expired rows.

### 4.12 M-12 — `GET /api/parkings/{parkingId}` passes an empty `viewerId`
`backend/lib/routes/parking_routes.dart:82-94`
```dart
requireUserId(req);                     // result discarded
final payload = await _service.getById(parkingId, viewerId: userIdOf(req), …);
```
`requireUserId()` (`backend/lib/middleware/auth_middleware.dart:87-98`) **verifies** the token but never writes `request.context`, so `userIdOf(req)` returns `''`. Today `ParkingService.getById` ignores `viewerId` (`parking_service.dart:136-203`), so there is no live data leak — but this is a latent IDOR: the moment `getById` uses `viewerId` for owner-only fields (or a private listing is added) the endpoint becomes broken-open. Same discarded-result pattern at `payment_routes.dart:27`. Fix: use the returned id.

### 4.13 M-13 — No rate limiting / request-size limits on the whole API
`backend/bin/server.dart:24-28` — no `shelf` rate-limit middleware, no max body size on JSON routes. `readJsonBody` (`middleware.dart:69-79`) reads the whole body into memory. Combined with `POST /api/uploads` being open to all roles, this is a cheap DoS.

### 4.14 M-14 — Refresh-token rotation has no reuse detection
`backend/lib/services/auth_service.dart:161-210` revokes the presented token and issues a new pair, but does **not** revoke the token's family when an already-revoked token is presented (`auth_service.dart:182-184` merely returns 401). Best practice: on replay of a revoked token, revoke the entire family/user. Medium because the token hash is the DB key and guessing is infeasible.

### 4.15 M-15 — Android `allowBackup` not disabled
`android/app/src/main/AndroidManifest.xml:9-12` — `<application>` has no `android:allowBackup="false"`. `flutter_secure_storage` (`lib/core/storage/token_storage.dart:11-13`, `encryptedSharedPreferences: true`) holds JWTs in encrypted SharedPreferences; ADB/cloud backup of that file widens the exposure window. Fix: `android:allowBackup="false"` (+ `android:fullBackupContent`/`dataExtractionRules`).

### 4.16 M-16 — No HTTPS/TLS enforcement server-side
The API has no TLS termination, no HSTS, and no redirect-to-HTTPS. Dev defaults in both `ApiConstants` and `publicUrlFor` are plain HTTP. Deployment concern (must be terminated at a proxy/load balancer); documented, not fixable in-repo.

### 4.17 M-17 — `GET /api/payments/parking/{parkingId}/owner` exposes the owner's phone and UPI ID to any authenticated user
`backend/lib/routes/payment_routes.dart:26-30` → `PaymentService.ownerPaymentInfo` (`payment_service.dart:40-75`) returns `ownerPhone` and `ownerUpiId` to **any** authenticated account (any role, any relationship to the parking). Needed for the COD contact flow, but it is an unauthenticated-scope PII/financial-identifier disclosure and should be rate-limited / limited to users with a booking relationship or an active intent. Reported; not changed (would break the working COD screen).

---

## 5. Low findings

| ID | Finding | Location | Notes |
|---|---|---|---|
| L-01 | Generated/dev artifacts shipped in the package: `build/`, `.dart_tool/`, `.idea/`, `parkshare_new.iml`, `backend_run*.log`, `build_err.txt`, `e2e_run.txt`, `e2e_final3.txt`, `e2e_final4.txt`, `run_app*.log`, `backend/audit_run*.log`, `backend/backend_*.log`, `backend/uploads/` (~130 test PNG/JPG incl. 18-byte and 70-byte stubs), `backend/.dart_tool` | repo root, `backend/` | No functional impact; inflates the package, may contain internal error text. **Reported, not deleted** (they are the user's local artifacts). Root `.gitignore` lacks `/backend/.dart_tool/`, `/backend/uploads/`, `/backend/*.log`. |
| L-02 | `android/local.properties` carries a machine-specific SDK path | `android/local.properties` | Normally gitignored; harmless locally, must never be shared. |
| L-03 | Google Sign-In is **MISSING** | `pubspec.yaml:10-44` | Not a dependency, no UI, no backend route. The only match in the tree is a stale build-cache artifact. Login is email+password only. |
| L-04 | Esri tile User-Agent is the placeholder package name | `lib/core/constants/map_tiles.dart:40` | Attribution text is present (Esri terms satisfied), but the UA is not an identifying app identity — see H-07. Map provider deliberately **not** changed. |
| L-05 | Dev REST tool hardcodes a test password | `tool/rest_suite.ps1` | Dev-only script, not shipped in the app. Rotated/ignored; flagged so it never becomes a real credential. |
| L-06 | Dev OTP UI compiled into release | `lib/modules/auth/screens/otp_verification_screen.dart:42-48,157-174` | See H-08. |
| L-07 | `ApiClient` builds URIs by string concatenation without segment encoding | `lib/core/network/api_client.dart:62,159` | All interpolated ids are server-issued UUIDs, so no exploit path today; would matter if a user-supplied string ever reaches a path. |
| L-08 | Unused/duplicated parameters and dead branches | `ParkingService.getById(viewerId:)` (`parking_service.dart:136-138`), `payment_service.dart:145-159` (`reference = COALESCE(reference, @ref)` after `createUpiIntent` always sets it) | Harmless; flagged for cleanup. |
| L-09 | 39 Flutter + 3 backend packages have newer versions blocked by constraints | `flutter pub outdated`, `dart pub outdated` | No security-advisory bumps pending; upgrading is a maintenance task, not an audit fix. |
| L-10 | Backend has **zero** tests and no `test` dev-dependency | `backend/pubspec.yaml:19-20`, V5 | Fixed as part of this audit (security regression tests added). |
| L-11 | `print()` used directly in services/config (dev-style logging) | `auth_service.dart:277`, `config.dart:58`, `middleware.dart:88,91` | Only `auth_service.dart:277` leaks a secret (H-02). |
| L-12 | No CSRF tokens | — | **Not applicable**: the API is Bearer-token only, no cookies, `SameSite` n/a. Explicitly verified rather than assumed. |
| L-13 | `readJsonBody` swallows malformed JSON | `backend/lib/middleware/middleware.dart:69-79` | A malformed body becomes `{}`, producing a 400 with a field-specific message — acceptable UX, slightly confusing diagnostics. |
| L-14 | `assert`-free internal invariants on payment transitions | `payment_service.dart:190-194,421-428` | Idempotency guards are present and correct (verified for both UPI and COD). |
| L-15 | COD confirm transaction ID is server-generated, not a real receipt | `payment_service.dart:436,447` | `TXN…` is a settlement record id, not a gateway reference. Semantics should be documented (and are, after the fix). |
| L-16 | No structured/JSON logging | `backend/bin/server.dart:78-82`, `middleware.dart` | Logs are free text; no correlation ids. |
| L-17 | `is_active` is checked on login and `/me` but not on every request | `auth_service.dart:146-148,218-220` | A deactivated user keeps a working access token until it expires — which, per H-04, is forever. Fixed together with H-04/H-06 hardening (shorter token life + refresh-time check). |
| L-18 | Phone numbers stored and returned in cleartext | schema + `booking.dart:92-107` | Standard for a contact feature; flagged for a future data-protection review. |
| L-19 | No dependency lockfile committed for the backend | `backend/.gitignore:5` ignores `pubspec.lock` | For an application (not a package) the lockfile **should** be committed. Low, but it means backend dependency versions are not reproducible. |

---

## 6. Positive controls verified (things that are already correct)

These were checked specifically so the fix phase does not "fix" them and regress them.

1. **SQL injection — clean.** Every statement in `backend/lib/{routes,services,database}` uses `Sql.named` with bound `parameters`. The only string interpolation is generated `@id0…@idN` placeholders and internally-known table/column names (see the dynamic `IN (…)` builder in `parking_space_service.dart`). No user input is ever concatenated into SQL. `sql/migrations/004_owner_upi_cod.sql` prevents overlap at the **database** level with `EXCLUDE USING gist (parking_space_id WITH =, daterange(start_date,end_date,'[]') WITH &&)`.
2. **Passwords** — bcrypt with per-password salt (`auth_service.dart:99,143,320`). Comparison via `BCrypt.checkpw`.
3. **JWT verification** — `auth_middleware.dart:43-77` decodes the header, requires `alg == 'HS256'`, rejects `none`, requires `type == 'access'`. Algorithm confusion is correctly mitigated. *Missing `exp` (H-04).*
4. **Refresh tokens** — stored as SHA-256 hashes only (`:461`), rotated on use (`:200-208`), revocable, and all are revoked after a password reset (`:334-339`). Good.
5. **IDOR / role audit of every endpoint** — verified individually:

   | Endpoint | Guard | Verdict |
   |---|---|---|
   | `POST /api/auth/register` | public | OK |
   | `POST /api/auth/login` | public, generic error on bad creds (`:140,144`) | OK |
   | `POST /api/auth/refresh` | token-hash lookup | OK |
   | `GET /api/auth/me` | `authMiddleware` | OK |
   | `POST /api/auth/logout` | revokes own token | OK |
   | forgot / verify / reset password | see H-03/H-05 | weak |
   | `POST /api/parkings` | `authMiddleware(allowedRoles:['owner'])` | OK |
   | `GET /api/parkings/nearby` | any authenticated | OK (by design) |
   | `GET /api/parkings/owner/{ownerId}` | `me != ownerId → 403` | OK |
   | `GET /api/parkings/{parkingId}` | token required; `viewerId` empty | OK but latent (M-12) |
   | `GET /api/parkings/{id}/spaces`, `/availability` | `authMiddleware` | OK |
   | `PUT/DELETE /api/parkings/{id}` | owner role + `owner_id` match in service | OK |
   | `POST /api/vehicles` | `userIdOf` (own only) | OK |
   | `GET/PUT/DELETE /api/vehicles/{id}` | `me != vehicle.user_id → 403` (`vehicle_routes.dart:44,50,61`) | OK |
   | `POST /api/bookings` | `userIdOf` (own only) | OK |
   | `GET /api/bookings/owner/{id}`, `/user/{id}` | `me != id → 403` | OK |
   | `GET /api/bookings/{id}` | `getById(viewerId: me)` checks `user_id`/`owner_id` | OK |
   | `PUT /api/bookings/{id}/accept|reject` | owner role + `_transition` checks `owner_id` | OK |
   | `POST /api/payments/upi/intent` | `_payableBooking(viewerId: userIdOf)` | OK |
   | `POST /api/payments/upi/confirm` | `_payableBooking(viewerId: userIdOf)` | authz OK, **integrity CRITICAL (C-01)** |
   | `POST /api/payments/upi/fail` | `_payableBooking(viewerId: userIdOf)` | OK |
   | `POST /api/payments/cod` | `_payableBooking` + `beginCod(userId)` | OK |
   | `PUT /api/payments/{id}/cod/confirm` | `requireUserIdOfRole(['owner'])` + owner-derived id + status guard | OK, idempotent |
   | `GET /api/payments/parking/{id}/owner` | any authenticated | OK but over-broad (M-17) |
   | `POST /api/payments` (legacy) | `userIdOf` | **integrity CRITICAL (C-01)** |
   | `GET /api/inbox/conversations` | `listFor(userIdOf)` | OK |
   | `POST /api/inbox/conversations` | `ensureConversation(requesterId: userIdOf)` | OK |
   | `GET/POST /api/inbox/conversations/{id}/messages` | `requireUserId` + `InboxService._assertParticipant` | OK |
   | `POST /api/uploads` | any authenticated | over-broad (M-02) |
   | `GET /uploads/*` | **public by design** (parking photos) | OK (with M-02/M-03 caveats) |
   | `GET /health` | public | OK |

6. **Upload path traversal** — filenames are always server-generated random names (`media_storage.dart:45-48`); `serve()` takes only the last path segment. No traversal is currently reachable. The `startsWith` guard (M-03) is still wrong.
7. **Flutter secure storage** — `flutter_secure_storage` with `encryptedSharedPreferences: true` (`token_storage.dart:11-13`). Tokens are **not** in `SharedPreferences`. (Backup caveat: M-15.)
8. **Debug-only cleartext traffic** — `usesCleartextTraffic` is confined to `android/app/src/debug/AndroidManifest.xml`; the main manifest (`:1-104`) does **not** enable it. Good.
9. **Double-submission guards in the payment UI** — `payment_screen.dart` and `payment_provider.dart` guard with a `_processing` flag plus `mounted` checks; the explicit "I have paid" confirmation is required only when a UPI app actually took over. Do not regress.
10. **COD flow correctness** — `confirmCod` (`payment_service.dart:415-462`) is fully idempotent: it early-returns for `CONFIRMED`/`ACTIVE`, rejects any state other than `COD_PENDING`, derives the actor from the JWT (`ownerId`), and only the `COD_PENDING → COD_CONFIRMED` UPDATE can ever move money. **Must be preserved exactly.**
11. **No hardcoded credentials in the shipped app.** `tool/rest_suite.ps1` has a dev test password (L-05); no credential appears in `lib/` or `backend/lib/`.
12. **No secret printed by `Config.load()`** — it prints host/port/db name/smtp-enabled/max-bytes only (`config.dart:56-63`). No `.env` value is echoed anywhere in the source.

---

## 7. Schema / migration audit

| File | Status |
|---|---|
| `001_auth.sql` | Sound. Gaps: no index on `password_reset_otps.otp_hash`, no `attempts`/`last_sent_at` (M-11, H-05). |
| `002_parking_booking.sql` | Sound. |
| `003_parking_slots.sql` | Sound. |
| `004_owner_upi_cod.sql` | Sound and well-documented; enforces `bookings_status_check`, `bookings_payment_method_check`, `bookings_payment_status_check`, `payments_payment_method_check`, `payments_payment_status_check`, `users_upi_id_format`, plus the overlap `EXCLUDE` constraint. |
| **New** | `005_security_fixes.sql` — required by this audit: adds the `UPI_PENDING_VERIFICATION` status to both CHECK constraints (idempotently), adds `attempts`/`last_sent_at` to `password_reset_otps`, indexes `otp_hash`/`last_sent_at`. Additive, idempotent, non-destructive, and **does not** retro-modify any applied migration. |

---

## 8. Remediation plan (executed in `AUDIT_FIX_LOG.md`)

| # | Action | Findings |
|---|---|---|
| F1 | Rework `PaymentService.confirmUpi` — require a `PENDING` row, never fabricate a transaction ID, never insert `SUCCESS`, record `UPI_PENDING_VERIFICATION`, keep the booking out of `CONFIRMED`/earnings; add owner/admin settlement | C-01, C-02 |
| F2 | Remove the legacy `create()` fabrication path | C-01 |
| F3 | `005_security_fixes.sql` (new, idempotent) | C-01, H-05, M-11 |
| F4 | `config.dart` — production guard for `JWT_SECRET`; `APP_ENV`; `ALLOW_DEV_OTP`; `CORS_ALLOWED_ORIGINS`; OTP attempt/cooldown/rate-limit knobs; required `PUBLIC_BASE_URL` in production; fail-fast `Config.validateForStartup()` called from `bin/server.dart` | H-01, H-02, M-01, M-17 |
| F5 | `auth_service.dart` — stop printing/returning the OTP unless `ALLOW_DEV_OTP`; generic forgot-password/verify responses; OTP attempt cap; resend cooldown; `exp`/`iat` claims on both tokens; `createUpiIntent`-gated settlement | H-02, H-03, H-04, H-05, M-08, M-10 |
| F6 | CORS allow-list + `securityHeadersMiddleware` + quiet production error logging | M-01, M-04, M-05, M-06 |
| F7 | Upload hardening — magic-byte sniffing, sniffed extension, executable rejection, owner-only route, canonical path check | M-02, M-03 |
| F8 | Fix `viewerId`/discarded-`requireUserId` patterns | M-12 |
| F9 | `Random.secure()` for all generated identifiers | M-07 |
| F10 | Flutter — gate dev OTP behind `kDebugMode` + `ALLOW_DEV_OTP`; release-mode `API_BASE_URL` assertion; `android:allowBackup="false"`; dev tools behind `kDebugMode` | H-02, H-08, L-04, L-06, M-15 |
| F11 | Android signing config driven by `key.properties` with a **hard failure** when the keystore is absent | H-06 |
| F12 | Backend test harness (`test` dev-dependency) + focused security tests | L-10 |
| F13 | Re-verify: `dart analyze`, `dart test`, `flutter analyze`, `flutter test`, live backend `/health`, `flutter devices`/run, `flutter build apk --release` + `appbundle` | — |

**Explicitly NOT done (by instruction):** changing the `applicationId`; installing a keystore; rotating the `.env` secrets (recommended, requires the owner's action); changing the map provider; deleting the user's local log/upload artifacts; creating any UI bypass or fake-success path; suppressing analyzer findings.

---

## 9. Residual risk after remediation

* **UPI settlement still cannot be cryptographically verified** by this backend. After F1/F2 the server records a *claim* (`UPI_PENDING_VERIFICATION`) and waits for the owner to settle it, exactly as COD does. This is the honest and safe behaviour; a PSP webhook (`collect.request`/`payment.captured`) is the real fix and must be integrated before marketing UPI as instant.
* **UPI pending payments now hold no slot** until settlement, which changes visible availability behaviour. This is intentional and documented in `AUDIT_FIX_LOG.md` (F1) — an unverified payment must not consume inventory, exactly like `COD_PENDING` does not.
* Release signing and the Play `applicationId` remain owner decisions (H-06/H-07); the build is now set up to *fail loudly* rather than ship a debug-signed artifact.
* TLS/HSTS termination remains an infrastructure responsibility (M-16).

---

*End of `AUDIT_REPORT.md` — see `AUDIT_FIX_LOG.md` for the applied changes with before/after evidence.*
