# ParkShare — Phase 1 (Authentication) Completion Report

**Status: ✅ PASS (end-to-end verified on emulator-5554)**

Date: 2026-09-23

---

## 1. What was delivered

### Backend — Dart Shelf REST API (`backend/`, port 8080)
- Config from env (`backend/.env`): DB creds, JWT secret, SMTP (optional).
- PostgreSQL connection pool + idempotent migration runner (`schema_migrations`).
- Error, CORS and JWT-auth middleware with API envelope `{success, message, data}`.
- **8 auth APIs** (all under `/api/auth`):

| # | Method | Path | Purpose |
|---|--------|------|---------|
| 1 | POST | `/register` | Create account (auto-login, returns tokens) |
| 2 | POST | `/login` | Login (role enforced → 403 on mismatch) |
| 3 | POST | `/refresh` | Rotate refresh token (old one revoked) |
| 4 | GET  | `/me` | Current user from access token |
| 5 | POST | `/logout` | Revoke refresh token |
| 6 | POST | `/forgot-password` | Issue OTP (dev: returned as `devOtp`) |
| 7 | POST | `/verify-reset-otp` | Validate OTP (reuse rejected) |
| 8 | POST | `/reset-password` | Set new password, invalidate OTPs |

- Passwords **BCrypt-hashed**; **JWT (HS256)** access tokens with random `jti`; refresh tokens stored as **SHA-256 hashes** with rotation + revocation.
- OTPs stored hashed, expire in 10 min, deleted after reset (reuse → 400).
- Backend test suite: **23/23 PASS** (`.NET HttpClient` script — `auth_api_test.ps1`).

### Database — PostgreSQL (`parkshare` @ 127.0.0.1:5432)
Migration `001_auth.sql` created **3 tables**: `users`, `refresh_tokens`, `password_reset_otps`.

### Flutter app (`lib/`, feature-based structure)
- Provider wiring in `app/app.dart`; **green theme = Owner, blue theme = Vehicle User**.
- Screens: Splash (persistent-login restore), Onboarding, Role Selection, Login, Register, Create Password, Forgot Password, OTP, Reset Password, Owner Dashboard (shell), User Home (shell).
- Architecture: `core/` (constants, network `ApiClient`, storage `flutter_secure_storage` + session storage, utils), `shared/` (User model, widgets: PrimaryButton, CustomTextField, Loading, Empty, Error states), `modules/{splash, onboarding, auth, owner, user}`.
- All measurements in **meters only**; no AR/3D/FCM in this phase.
- Android: INTERNET + location + notification permissions; debug-only cleartext HTTP (10.0.2.2). iOS: Info.plist location/camera/photo usage strings.

## 2. Test evidence

| Check | Result |
|-------|--------|
| `dart analyze` (backend) | ✅ No issues |
| `flutter analyze` | ✅ No issues |
| Backend API suite | ✅ **23/23 pass** |
| Widget smoke test (`test/widget_test.dart`) | ✅ 1/1 pass |
| **Integration test on emulator-5554** (`integration_test/auth_flow_test.dart`) | ✅ **All tests passed (00:30 +1)** |

### Integration flow verified end-to-end on the emulator
1. Cold boot (no session) → Splash → Onboarding → Role Selection
2. **Vehicle User register** (details → create password) → **User Home**
3. **Persistent login**: app relaunch → session restored → User Home
4. **Logout** → Role Selection; relaunch → Onboarding (tokens cleared)
5. **Login** with stored credentials → User Home
6. **Forgot password**: email → OTP (dev auto-fill) → verify → reset → success banner → old password rejected (401) → **new password login** ✓
7. **Parking Owner register** → **Owner Dashboard**
8. Owner persistent login across relaunch
9. Final logout → relaunch → Onboarding

### Database verification (post-run)
- `users`: 10 — both `Test Driver` (user) and `Test Owner` (owner) rows with BCrypt `$2a$10$...` hashes.
- `refresh_tokens`: 18 — stored as SHA-256 hex (64 chars), 13 revoked (rotation/revocation exercised).
- `password_reset_otps`: 0 — rows are deleted by design after reset completes (insert → verify → delete); the empty table confirms the forgot-password cycle ran.

Screenshot: [`docs/phase1_screenshot.png`](docs/phase1_screenshot.png)

## 3. Known issues / notes
- **OTP delivery**: SMTP not configured, so the backend logs the OTP to console and returns it as `data.devOtp` (shown on the OTP screen). Safe to remove once SMTP is wired.
- **Cleartext HTTP** is allowed for **debug builds only** (`android/app/src/debug/AndroidManifest.xml`); release builds remain secure (HTTPS in Phase 2+).
- Integration-test run exits with code 1 in PowerShell due to Gradle/JVM stderr warnings; `flutter` itself reports "All tests passed!".
- Widget smoke test mocks the `flutter_secure_storage` method channel (no native plugin in unit tests).

## 4. Ready for
Phase 2 (parking-space listing CRUD + owner dashboard data) — schema evolution via new migrations.