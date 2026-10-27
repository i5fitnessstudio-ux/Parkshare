# ParkShare Completion Report

**Date:** 2026-10-26  
**Scope:** Local payment state, Razorpay online collection, booking confirmation, owner earnings, manual owner payouts, encrypted payout details, tests, and Android release readiness.  
**Working tree:** `C:\Parkshare_new`  
**Verdict:** **NO-GO for production / Play Store release today.** The code-level blockers found in this audit are repaired and tested. The remaining blockers are external: no deployed HTTPS backend, no real Razorpay checkout/webhook evidence, no live-mode proof, no real manual payout proof, and no physical-device sign-off.

> No real payment, payout, bank-detail change, production deployment, or Razorpay Live Mode activation was performed. The only database used was the local development database `parkshare`, which is not production. Release verification used the deliberately non-routable placeholder API host `https://api.invalid.example`; that artifact was deleted.

---

## 1. Executive summary

### What is now complete locally

- Online payment success is **atomic**: payment success, booking confirmation, booking history, and owner-earning creation commit in one transaction. A failure rolls all of them back.
- Razorpay checkout verification and webhooks are **idempotent** and heal an already-successful payment that is missing its booking/ledger writes.
- A failed Razorpay checkout or `payment.failed` webhook now marks **both** the payment and the booking payment state as failed. A late failure cannot overwrite a successful payment.
- A captured payment for a non-payable/cancelled booking is **not** recorded as a normal success; the transaction is rejected and requires manual review/refund. This is audited as a residual operational runbook item.
- The client cannot create a second order for a booking whose last checkout result is still unverified. It re-verifies the stored claim instead of charging again.
- Checkout cancellation, stale callbacks, app disposal, and account switching terminate in-flight sessions safely. A replaced account cannot write payment state for the previous account.
- Owner payout details now include the **full bank account number and IFSC**, encrypted at rest with AES-256-GCM. Existing last-4-only data is not guessed or reused.
- Owners still see only masked metadata. Full decrypted details are available only through an ADMIN-only, `no-store` endpoint for one transfer.
- Manual settlement now has an admin queue, an admin payout-destination lookup, and a required external payout reference (UTR / bank / UPI transaction id). Test-mode earnings remain audit-only and cannot be marked settled.
- The owner UPI id is **optional legacy metadata**. It is not required for Razorpay checkout, COD, or manual bank payouts.

### What is not proven

- No backend is deployed to an HTTPS environment.
- No real Razorpay test-mode Checkout has completed through this backend, and no signed webhook has been received.
- No live-mode payment, refund, or manual payout has been executed.
- The local development database contains **zero** Razorpay orders/payments/mode rows, **zero** transfers, and **zero** webhook events. It cannot serve as production payment evidence.
- The local database has **zero** owner accounts with encrypted payout details. The one existing owner account has only legacy last-4 data and must re-submit.
- No physical Android device QA, Play Console data-safety review, privacy policy publication, or production URL is available.

**Therefore the only correct production verdict is NO-GO until the external evidence in Sections 7–9 is supplied.**

---

## 2. Changes made

No Git repository exists in this workspace, so a commit diff is unavailable. The changes below were made directly in the working tree and verified by analysis/tests.

### 2.1 Backend payment state and atomicity

| File | Change |
|---|---|
| `backend/lib/services/razorpay_payment_service.dart` | Payment lock/update, booking confirmation, history, and owner-earning insert now run in one transaction. Route transfer, if ever enabled, runs only after commit. Repeated verification/webhooks are idempotent and heal partial success. Failed checkout and `payment.failed` webhooks are mirrored to the payment and booking. Captured-but-not-payable payments are rejected instead of falsely confirmed. |
| `backend/lib/services/booking_service.dart` | Transaction-scoped online booking confirmation with row locking, status and payment-method safety, zero-row detection, history append, and rollback. |
| `backend/lib/services/payment_service.dart` | Booking payment-state healing covers any non-COD booking, including `ACTIVE`; owner settlement totals remain server-computed. |
| `backend/lib/routes/webhook_routes.dart` | Raw-body signature verification preserved; webhook remains `POST /api/webhooks/razorpay`. |

### 2.2 Owner payout architecture and encrypted destination

| File | Change |
|---|---|
| `backend/lib/services/payout_details_cipher.dart` | New AES-256-GCM encryption/decryption with tamper rejection. |
| `backend/lib/services/owner_payment_account_service.dart` | Saves full account number + IFSC encrypted; validates account/IFSC; preserves provider-owned onboarding state; returns a strict masked owner projection. |
| `backend/lib/services/admin_settlement_service.dart` | Pending-settlement queue, single-transfer payout destination, required non-empty external payout reference, ADMIN-only access, test/unknown-mode refusal, and decryption-error refusal. |
| `backend/lib/routes/admin_routes.dart` | ADMIN-only settlement routes. Payout destination response is `no-store` / `no-cache`; it is never logged or cached. |
| `backend/lib/config/config.dart` | Production startup now requires a stable `OWNER_PAYOUT_ENCRYPTION_KEY` of at least 32 characters. Missing/weak key refuses boot before the socket is bound. |
| `backend/sql/migrations/012_owner_payout_details.sql` | Additive migration: encrypted account/IFSC columns, timestamp, and payout-ready index. Migration is applied locally. No destructive statement. |
| `deploy/parkshare-prod.env.example` | Documents the payout encryption key and production requirements. |

### 2.3 Client payment lifecycle and account isolation

| File | Change |
|---|---|
| `lib/core/services/razorpay_payment_service.dart` | Checkout can be cancelled; plugin reset and abandoned future completion; stale callbacks are rejected. |
| `lib/modules/booking/providers/payment_provider.dart` | Session-epoch guards; pending-claim booking scope; a second order is refused for an unverified claim and the claim is re-verified; permanent errors clear the claim; COD and online state handling fixed. |
| `lib/app/app.dart` | Provider resets moved from `build` to an auth identity-change listener. |
| `lib/modules/booking/providers/booking_provider.dart` | Account-switch reset and stale-response guard. |
| `lib/modules/owner/providers/owner_payments_provider.dart` | Account-switch reset and stale-load guard. |
| `lib/modules/owner/providers/owner_dashboard_provider.dart` / `owner_parking_provider.dart` | Account-switch reset wiring. |

### 2.4 Documentation/comment corrections

- Removed stale claims that an owner UPI id was mandatory for registration.
- Removed stale claims that payout data was stored only as last-4.
- Removed stale claims that `settledPaise` could only change through Razorpay Route.

### 2.5 Tests added or extended

- `backend/test/payout_details_cipher_test.dart` — AES-GCM round-trip, wrong key, tampering.
- `backend/test/config_startup_validation_test.dart` — production boot refusal without a payout key, and no secret value in boot output.
- `backend/test/manual_settlement_test.dart` — ADMIN authorization, payout-reference validation, empty-reference rejection, pending queue/destination.
- `backend/test/integration/payment_flow_integration_test.dart` — atomic rollback, failed webhook mirroring, duplicate verification/webhook, encrypted-at-rest, test-mode refusal, manual settlement, owner isolation, COD.
- `test/unit/payment_provider_session_test.dart` — account switch, stale response, pending re-verification without a second order, disposal.
- `test/unit/owner_payments_provider_test.dart` — owner account-switch reset and stale-load rejection.

---

## 3. Verification evidence

All commands were run on **2026-10-26** in this workspace.

| Check | Command | Result |
|---|---|---|
| Flutter static analysis | `flutter analyze` | **No issues found.** |
| Flutter tests | `flutter test` | **197 passed.** |
| Backend static analysis | `dart analyze` (in `backend`) | **No issues found.** |
| Backend unit/default suite | `dart test` (in `backend`) | **225 passed, 15 skipped** (the DB-backed suite is skipped unless explicitly enabled). |
| DB-backed money-path suite | `PARKSHARE_TEST_DB_*` pointed at local `parkshare`; `dart test test/integration/payment_flow_integration_test.dart` | **15 passed.** Migrations 001–012 applied. Test rows use the `itest-` prefix and are removed by `tearDownAll`. |
| Android release package | `flutter build appbundle --release --dart-define=API_BASE_URL=https://api.invalid.example` | **Built successfully**, 57.5 MB AAB. |
| Android signature | `jarsigner -verify app-release.aab` | **`jar verified.`** Exit code 0; only the expected self-signed upload-key warning. |
| Placeholder artifact cleanup | Deleted `build/app/outputs/bundle/release/app-release.aab` | Deleted because it targeted `https://api.invalid.example` and must never be distributed. |
| Signing certificate validity | Keytool inspection of the configured upload key | Valid **2026-10-10 through 2054-02-25**; alias `upload`; one private-key entry. |

### Local database audit (development data only)

| Metric | Count |
|---|---:|
| Payments total | 47 |
| Payments with status `SUCCESS` | 8 |
| Payments with a Razorpay order id | 0 |
| Payments with a Razorpay payment id | 0 |
| Payments with a Razorpay mode | 0 |
| `payment_transfers` rows | 0 |
| Transfers with settlement status `SETTLED` | 0 |
| Razorpay webhook events | 0 |
| Owner payment accounts | 1 |
| Owner accounts with encrypted account + IFSC | 0 |

**Interpretation:** the local database proves nothing about Razorpay online collection or settlement. Its 8 `SUCCESS` rows predate/are outside the Razorpay path and have no gateway identifiers. This is why the report does not claim live payment readiness.

---

## 4. Payment readiness

### 4.1 Ready at code level

| Capability | Status | Evidence |
|---|---|---|
| Server-authoritative order amount | Ready | Amount is read from the booking; client-supplied amount is ignored. |
| Checkout signature verification | Ready | HMAC verification before any paid state. |
| Webhook HMAC verification | Ready | Raw body passed unchanged to verifier; invalid signature is rejected. |
| Idempotent success | Ready | Repeated verification/webhook cannot create a second earning or overwrite a different payment id. |
| Atomic payment + booking + ledger | Ready | Single transaction; integration rollback test. |
| Failed payment mirroring | Ready | Checkout and webhook failure paths; SUCCESS is protected from late failure. |
| Duplicate-charge prevention | Ready | Pending unverified claim is re-verified, not replaced by a new order. |
| Account-switch isolation | Ready | Session epoch and stale-response guards; unit tests. |
| Owner UPI independence | Ready | UPI is optional metadata; not used by Razorpay or COD. |
| COD | Ready | Existing flow preserved; owner confirms cash; one earning row. |

### 4.2 Not proven / not ready for production

1. **No HTTPS deployment.** The app refuses to run in release without an explicit `API_BASE_URL`, and Android release builds refuse cleartext. No production HTTPS endpoint is deployed.
2. **No real Razorpay test-mode end-to-end run.** There is no completed Checkout through this backend, no captured test payment, no signed webhook delivery, and no local gateway identifiers.
3. **No Live Mode activation.** Local configuration is `RAZORPAY_MODE=test` with test keys; live keys and webhook secret are absent. Live-mode behavior is untested.
4. **No physical-device checkout evidence.** Razorpay Checkout is a native plugin; unit tests use a fake. A real Android device run is still required for the UPI/card sheet, app backgrounding, cancellation, and callback timing.
5. **No automated refund implementation.** If a payment is captured in the narrow race where the booking is no longer payable, the transaction rejects and the money requires a manual Razorpay refund. A written refund/reconciliation runbook is required before live traffic.
6. **No scheduled gateway reconciliation.** Healing depends on webhook retries or a user retry. A daily Razorpay settlement report vs. local ledger reconciliation is not implemented; add it before meaningful volume.

### 4.3 Local configuration boundary

Local `backend/.env` remains development/test configuration: `APP_ENV=development`, `RAZORPAY_MODE=test`, `RAZORPAY_ROUTE_ENABLED=false`, a `rzp_test` key prefix, no webhook secret, and no payout encryption key. It must not be copied to production unchanged.

---

## 5. Settlement readiness

### 5.1 Razorpay Route decision

**Razorpay Route is not an immediate dependency.** Its onboarding/eligibility is an external commercial and compliance process, not a code toggle. The requirements reviewed for this audit included business turnover evidence (the published Route threshold for FY25/FY26 was above ₹40 lakh domestic turnover), payer–payee transparency approval, and compliance with the RBI cut-off that took effect on 31 December 2025. Those conditions have not been demonstrated for this business.

Consequences:

- `RAZORPAY_ROUTE_ENABLED` remains **false**.
- No linked-account onboarding is faked.
- No transfer id is invented.
- No transfer is reported as completed.
- Online earnings remain internal `PENDING` until an administrator records a real manual payout.

### 5.2 Manual settlement fallback (implemented)

The supported fallback is:

1. Customer pays through Razorpay Checkout into the ParkShare account.
2. Payment success atomically confirms the booking and creates an owner earning / `payment_transfers` row in `PENDING`.
3. An ADMIN reads the pending queue.
4. For one transfer, the ADMIN reads the owner's full payout destination through the ADMIN-only endpoint.
5. The ADMIN performs the bank transfer outside ParkShare.
6. The ADMIN calls `mark-settled` with a **non-empty external payout reference** (UTR / bank / UPI transaction id) and optional note.
7. The row becomes `SETTLED`; the reference and acting admin id are stored; repeated settlement is idempotent.

Safety properties:

- Owner identity and amount always come from the ledger row, never from the request body.
- ADMIN role is required at the route boundary.
- Full account number/IFSC is AES-256-GCM encrypted at rest.
- Owner-facing responses expose only last-4 and `payoutDetailsAvailable`.
- The destination response is ADMIN-only, `no-store`, and not logged.
- Test-mode and unknown-mode earnings cannot be settled.
- A missing/undecryptable destination refuses the payout instead of guessing.

### 5.3 Remaining settlement blockers

1. **No real payout has been performed.** All local transfers are 0. A live-mode captured payment and a real small manual payout are still needed to prove the operational path end to end.
2. **Existing owner data is incomplete.** The one local owner account has only legacy last-4. After migration 012, the owner must re-submit full account number + IFSC. The migration deliberately did not invent or backfill values.
3. **No admin console.** Settlement is exposed as authenticated ADMIN REST endpoints, not a back-office screen. A controlled operator client is required; raw curl usage must never log the destination response.
4. **Key custody is external.** `OWNER_PAYOUT_ENCRYPTION_KEY` must be generated once, stored in a secret manager, backed up, and kept stable. Changing it makes existing ciphertext unreadable. Key rotation is not implemented.
5. **No payout reconciliation.** The operator must match every `SETTLED` row and reference against the actual bank statement. No automated bank reconciliation exists.

### 5.4 Owner UPI ID decision

**The owner UPI ID is not required for the supported payment architecture.** Razorpay Checkout uses ParkShare's gateway credentials; manual payouts use bank account + IFSC. The owner UPI field remains optional/backward-compatible and is not a payout dependency. The legacy direct-UPI flow is not offered by the production payment screen.

---

## 6. What happens on the important failure paths

| Event | Result |
|---|---|
| Checkout succeeds, backend verification fails temporarily | Client shows “Verifying payment…”, keeps the claim, and retries verification; it does not open a second order for the same booking. |
| App killed or account switched during Checkout | In-flight future is completed as cancelled; provider state is reset; stale callbacks cannot mutate the new account. |
| Webhook arrives before/after checkout verification | Idempotent; one payment, one booking confirmation, one earning. |
| Duplicate webhook | No second earning; booking remains confirmed. |
| `payment.failed` after a successful capture | Ignored for the successful row; cannot erase success. |
| Payment captured for a cancelled/non-payable booking | Transaction rejects, no false confirmation/earning; manual refund required. |
| Test-mode earning in production | Excluded from live totals and refused by manual settlement. |
| Owner has only last-4 details | Payout destination endpoint refuses and asks the owner to re-submit. |
| Admin attempts settlement without a reference | Validation error; no `SETTLED` state. |

---

## 7. External activation steps (required in order)

### Step 1 — Deploy the backend to HTTPS staging

- Provision the backend, PostgreSQL, persistent uploads, and a valid TLS certificate.
- Set production configuration (use non-secret names here; never commit values):
  - `APP_ENV=production`
  - `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
  - `JWT_SECRET` with at least 32 random characters
  - `PUBLIC_BASE_URL=https://<staging-host>`
  - `CORS_ALLOWED_ORIGINS` (explicit, no wildcard)
  - `OWNER_PAYOUT_ENCRYPTION_KEY` with at least 32 random characters, stored in a secret manager
  - `RAZORPAY_MODE=test`
  - `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` from the **test** dashboard
  - `RAZORPAY_WEBHOOK_SECRET` from the webhook configuration
  - `RAZORPAY_ROUTE_ENABLED=false`
  - `PARKSHARE_COMMISSION_PERCENT` as the approved commercial value
- Confirm startup validation passes and migrations 001–012 apply.
- Confirm `/health` over HTTPS and that no secrets appear in logs.

### Step 2 — Configure Razorpay test mode

- Webhook URL: `https://<staging-host>/api/webhooks/razorpay`
- Subscribe at minimum to:
  - `payment.captured`
  - `order.paid`
  - `payment.failed`
- Use the same webhook secret as `RAZORPAY_WEBHOOK_SECRET`.
- Perform one real test-mode Checkout from a physical device through the deployed backend.
- Verify, in order: order row created with a test order id; checkout signature verified; booking `CONFIRMED`; payment `SUCCESS`; one owner earning in `PENDING`; signed webhook stored and processed; duplicate delivery is a no-op; failed payment mirrors `FAILED`; owner totals exclude test money in live mode.
- Do not enable Route and do not mark any test earning as settled.

### Step 3 — Build the real release candidate

- Build with the actual HTTPS production/staging URL, never the placeholder:
  - `flutter build appbundle --release --dart-define=API_BASE_URL=https://<real-host>`
- Install the signed release on at least one physical Android device and repeat login, booking, checkout cancel/success, app background/foreground, pending-verification retry, COD, owner settlement setup, and owner earnings screens.
- Confirm no cleartext traffic, no token leakage, and correct behavior after account switching.

### Step 4 — Prove manual settlement with controlled live money

- Use a controlled, approved, low-value live transaction (or an explicitly approved provider sandbox that supports a real live-mode ledger; do not relabel test rows).
- Re-submit the owner's full payout details after migration 012.
- Look up the pending queue and the payout destination as ADMIN.
- Make and record a real small bank payout with its UTR/reference.
- Mark settled and verify the ledger row, owner totals, and bank statement all agree.
- This step cannot be satisfied by test-mode rows because the system intentionally refuses to settle them.

### Step 5 — Complete Play Store readiness

- Production API URL and deployed backend.
- Live Razorpay credentials, webhook secret, and a completed live pilot.
- Play Console app record, package ownership, upload-key enrollment/App Signing, and an unused version code.
- Store listing, screenshots, privacy policy URL, account-deletion instructions, Data safety form (location, account, payments, device identifiers), content rating, target audience, and any payment/location declarations.
- Physical-device sign-off and internal/closed testing evidence.
- Only then build the final signed AAB and promote it.

---

## 8. Play Store and release readiness

### Verified locally

- Package: `com.parkshare.nexzware`
- versionCode: `2`, versionName: `1.0.0`
- minSdk: `24`; targetSdk: `36`
- Release signing is enforced by Gradle when a release artifact is requested; debug builds still work without the release key.
- The configured upload-key certificate is valid until **2054-02-25**.
- Release build blocks cleartext traffic and uses system CAs only.
- App backup is disabled; data-extraction rules are configured.
- The AAB builds and its signature verifies.
- `android/key.properties`, `.env`, and keystore files are covered by `.gitignore`.

### Remaining release blockers

| Blocker | Why it blocks | Required evidence/action |
|---|---|---|
| No production/staging API | A release build without `API_BASE_URL` throws; a placeholder build is unusable. | Deploy HTTPS backend; build with the real URL. |
| No Razorpay production proof | Collection, webhook, atomic confirmation, and failure handling are untested outside unit/integration fakes. | Complete the test-mode physical-device run, then a live pilot. |
| No live settlement proof | No real transfer, no UTR, no bank reconciliation. | Controlled live payment + small manual payout. |
| No physical-device QA | Razorpay Checkout is native and asynchronous. | Device matrix run and sign-off. |
| Play Console/legal work not evidenced | Data safety, privacy policy, account deletion, content rating, testers, app signing. | Complete Play Console declarations and internal testing. |
| Version code availability unknown | versionCode 2 may already be consumed. | Check Play Console; increment before upload if needed. |
| Signing-key custody external | Losing the upload key blocks updates; a mismatched enrollment blocks upload. | Confirm Play App Signing enrollment and secure offline backup. |
| No admin settlement operator UI | Payouts are REST-only; manual mistakes are easier. | Controlled back-office client or documented operator procedure. |

The release AAB produced in this audit is **not distributable**: it points at `https://api.invalid.example` and was deleted.

---

## 9. Production verdict

## **NO-GO**

The local implementation is substantially stronger and passes all available automated checks, but a production verdict requires evidence that cannot be manufactured locally:

1. A deployed HTTPS backend with production-valid configuration.
2. A real Razorpay test-mode checkout through that backend, with a signed webhook and correct booking/payment/ledger state.
3. A controlled live-mode payment and a real manual owner payout with a bank reference.
4. Physical-device payment and settlement QA.
5. Play Store declarations, signing enrollment, and an unused version code.

Until all five are supplied, enabling Live Mode or publishing to production would be an evidence-free release.

A staging/test-mode deployment is **GO** now: the code is ready for that next step.

---

## 10. Exact next action

**Deploy this backend to an HTTPS staging host with `APP_ENV=production`, a stable `OWNER_PAYOUT_ENCRYPTION_KEY`, and Razorpay test keys plus a webhook secret, then complete one real test-mode Checkout and signed webhook through `https://<host>/api/webhooks/razorpay` and verify the atomic booking/payment/earning result before doing anything else.**

Do not activate Live Mode, do not enable Route, and do not perform a real payout until that test-mode evidence exists.

---

## Appendix A — Evidence boundaries

- No Git repository exists; this report is based on the current working tree and command output, not a diff.
- The local PostgreSQL database is development data. It must not be promoted to production.
- The integration suite ran against the local `parkshare` database and cleaned up its `itest-` rows. No production database was accessed.
- The release AAB was a packaging/signature check only; its placeholder API URL makes it undeployable by design.
- No credentials, bank account numbers, IFSC codes, JWTs, or webhook secrets are included in this report.
