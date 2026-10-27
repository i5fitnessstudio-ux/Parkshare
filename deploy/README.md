# ParkShare — VPS production deployment (Docker + existing Traefik)

This is the **proposal + runbook** for the leg:

```
LOCAL ✅  ->  VPS deployment  ->  HTTPS webhook  ->  Physical phone
        ->  Live Mode  ->  Small real payment  ->  Production complete
```

**Nothing here has been applied.** No file has been placed on the VPS, no
container touched, no Traefik config changed. Everything below is for your
review and approval first.

> **Why there is step 0:** the working copy on this Windows machine has **no**
> `docker-compose.yml` and **no** Traefik config (the only archive present is an
> old backend-only snapshot). The real network/entrypoint/certresolver names can
> only come from the VPS itself, so step 0 reads them. Nothing in this plan
> hardcodes a guess: the four values marked `# REPLACE` are filled from that
> output.

---

## Target architecture (matches your constraints)

```
Android app ─┐                         ┌─► parkshare-backend (Docker, :8080)
             ├─► https://api.<domain> ─┤
Razorpay ────┘      (existing Traefik)  └─► parkshare-db (PostgreSQL 17)
```

* Traefik keeps owning **80/443** and terminating TLS. No nginx, no second proxy.
* The backend is **not** published to the host in production; Traefik reaches it
  over the shared Docker network.
* No systemd unit for the Dart process — it stays a container.
* No unrelated container is modified.

---

## Deliverables in this folder

| File | Destination on VPS | Purpose |
|---|---|---|
| `inspect-vps.sh` | run from anywhere (read-only) | Discovers the real network / entrypoint / certresolver / service names |
| `docker-compose.prod.yml` | `/opt/parkshare/docker-compose.prod.yml` | Overlay that adds Traefik routing, the uploads volume, and removes the test port |
| `parkshare-prod.env.example` | copy to `/opt/parkshare/parkshare-prod.env` | Production config + secrets (chmod 600) |

---

## Step 0 — Inspect the live VPS (read-only, mandatory)

Copy `inspect-vps.sh` to the VPS (or just paste its contents into a shell) and run:

```bash
bash inspect-vps.sh | tee /tmp/parkshare-inspect.txt
```

It only runs `ls`, redacted `cat`, and `docker inspect`. It reveals:

1. the **external network name** Traefik is attached to,
2. Traefik's **HTTPS entrypoint** name and **ACME certresolver** name,
3. the real **service names** for backend and DB,
4. whether **uploads are currently persisted** (they are probably not),
5. which env vars the backend already has (names only).

Send that output back. The four `# REPLACE` values in
`docker-compose.prod.yml` get their real values from it.

---

## Step 1 — Know the production config blockers (from the code, not guesses)

`backend/bin/server.dart` runs `Config.validateForStartup()` **before binding the
socket**. With `APP_ENV=production`, the server **refuses to start** unless all of
these are true. This is by design (fail closed), and it is exactly the list that
must be satisfied to go live:

| Requirement | Current repo state | Action |
|---|---|---|
| `JWT_SECRET` set, not the published placeholder, ≥ 32 chars | local `.env` has a 64-char value | generate a **fresh** one |
| `PUBLIC_BASE_URL` set | not set | set to `https://api.<domain>` |
| `CORS_ALLOWED_ORIGINS` non-empty | not set | set to `https://api.<domain>` |
| `RAZORPAY_KEY_ID` + `_SECRET` set together | test keys in the audited deployment | keep test keys until Step 7 |
| `RAZORPAY_MODE` is exactly `test` or `live` | `test` | switch only with the key pair |
| `RAZORPAY_WEBHOOK_SECRET` set when Razorpay is enabled | test-only secret in the audited deployment | replace with a live webhook secret (Step 4) |

Also from the code:

* **Uploads are on the container filesystem** (`UPLOAD_DIR`, default `uploads`,
  relative to the process working dir). Without a volume, every owner photo is
  lost on the next `up -d`. The overlay fixes this with `parkshare_uploads`.
* **DB migrations auto-apply on boot** from `sql/migrations` (relative to the
  working dir). The existing image already does this — no action needed.

### ⚠️ Razorpay key/mode warning (verify before anything else)

The **key prefix and `RAZORPAY_MODE` must agree**. A key beginning
`rzp_test_` is test money; a key beginning `rzp_live_` is real money. Never put a
live key pair in a test deployment, and never set `RAZORPAY_MODE=live` while the
test keys are installed.

The audited deployment uses test keys (`rzp_test_...`), `RAZORPAY_MODE=test`,
and a test webhook secret. Do not print or commit the actual values. If a live
key was ever stored in plaintext (for example in an old note or archive),
rotate it in the Razorpay dashboard and treat the old key as compromised.

The backend now writes `payments.razorpay_mode` when it creates an order. That
column is the per-payment settlement guard: a `test` or legacy-null earning can
never be marked paid out, even after switching the server to live keys. Live
keys come only at Step 7.

---

## Step 2 — Pre-flight on the VPS (before applying the overlay)

```bash
cd /opt/parkshare

# 2a. Generate a fresh JWT secret
openssl rand -hex 48

# 2b. Create the production env from the template and fill every REPLACE_
cp /path/to/parkshare-prod.env.example ./parkshare-prod.env
nano ./parkshare-prod.env
chmod 600 ./parkshare-prod.env

# 2c. Confirm how the base compose currently exposes the backend
grep -n -A3 -B1 'parkshare-backend' docker-compose.yml
```

Make sure the **values in `parkshare-prod.env` are not also hardcoded** in the
base compose's `environment:` block — an inline `environment:` entry wins over
`env_file`. Remove any duplicated `APP_ENV`/`DB_*`/`RAZORPAY_*` lines from the
base file if present.

> **No SMTP / OTP requirement.** ParkShare authentication is register, login,
> refresh, `/me` and logout only. No OTP, email OTP, SMTP transport or email
> delivery is used, so there is nothing to provision here.

---

## Step 3 — Review the merged compose (still no changes)

```bash
cd /opt/parkshare
docker compose -f docker-compose.yml -f docker-compose.prod.yml config
```

Confirm in the output:

* `parkshare-backend` now shows your Traefik labels, the `parkshare_uploads`
  mount at `/data/uploads`, and **no** `8082:8080` host publish;
* the `traefik` external network resolves;
* `parkshare-db` is unchanged.

If `!reset []` errors on your Compose version, apply the fallback noted in the
file (edit the base `ports:` to `127.0.0.1:8082:8080`, or remove it).

---

## Step 4 — Razorpay dashboard: webhook + secret

In Razorpay Dashboard → **Settings → Webhooks → Add New Webhook**:

| Field | Value |
|---|---|
| Webhook URL | `https://api.<domain>/api/webhooks/razorpay` |
| Secret | generate a strong random string — put the **same** value in `RAZORPAY_WEBHOOK_SECRET` |
| Active events | `payment.captured`, `payment.failed` (optionally `order.paid`) |

**Do not subscribe `payment.authorized`** unless you are certain the account uses
automatic capture. The handler currently treats `payment.authorized` as paid,
which would confirm a booking before the money is actually captured. Note that
the handler currently supports exactly: `payment.captured`, `order.paid`,
`payment.authorized` (all treated as paid), and `payment.failed` (marked failed).
Any other event is recorded and ignored.

The endpoint is public (no JWT); it is authenticated **only** by the
`X-Razorpay-Signature` HMAC over the raw body. Traefik does not rewrite the body,
so the signature stays valid. Do **not** attach any Traefik middleware that
buffers/compresses/transforms the request.

---

## Step 5 — Apply (only after approval)

```bash
cd /opt/parkshare
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
docker compose -f docker-compose.yml -f docker-compose.prod.yml logs -f parkshare-backend
```

Watch the logs. A healthy boot prints, in order:

```
Config loaded: appEnv=production db=parkshare-db:5432/parkshare port=8080 ...
Database connection verified (parkshare-db:5432/parkshare)
Migration already applied: 001_auth.sql
...
ParkShare API listening on http://0.0.0.0:8080
```

If it exits before binding, the reason is printed explicitly (that is the
validator doing its job) — fix `parkshare-prod.env` and repeat.

### Verify over HTTPS

```bash
curl -sS https://api.<domain>/health
# -> {"success":true,"message":"Success","data":{"status":"ok",...}}

# HTTP must redirect to HTTPS
curl -sSI http://api.<domain>/health | grep -i location
```

---

## Step 6 — Physical phone (test keys)

Build a **release** APK pointed at the HTTPS domain. Release is mandatory here:
the app's `network_security_config.xml` blocks cleartext, and a release build
without `API_BASE_URL` throws by design.

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.<domain>
# install build/app/outputs/flutter-apk/app-release.apk on the phone
```

On the phone, exercise: register/login → map → book → **Pay online** → Razorpay
Checkout opens. With test keys this is a test-mode payment (no real money).

Then confirm the webhook path end-to-end:

```bash
# on the VPS
docker exec -it parkshare-db psql -U parkshare -d parkshare -c \
  "SELECT event_type, razorpay_order_id, processed_at FROM razorpay_webhook_events ORDER BY created_at DESC LIMIT 5;"
```

A `payment.captured` row with a non-null `processed_at` proves
Razorpay → Traefik → backend → DB.

---

## Step 7 — Live mode

Only once Steps 5–6 are green:

1. Razorpay Dashboard → generate **live** keys (`rzp_live_*`).
2. In `/opt/parkshare/parkshare-prod.env`, replace `RAZORPAY_KEY_ID` /
   `RAZORPAY_KEY_SECRET` with the live pair and set `RAZORPAY_MODE=live`.
   Keep the **same webhook secret** (or update both sides together).
3. Recreate just the backend:
   ```bash
   cd /opt/parkshare
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --no-deps parkshare-backend
   ```
4. Rebuild the phone app (same `API_BASE_URL`; no other change needed) and
   reinstall.
5. On the first backend boot, migration `011_razorpay_mode.sql` adds
   `payments.razorpay_mode` and labels legacy Razorpay rows `test`. The manual
   settlement endpoint refuses `test`/unknown modes, and live-mode owner totals
   exclude them. Existing test earnings are audit-only and must not be paid out.

`RAZORPAY_ROUTE_ENABLED` stays `false` unless Route is actually enabled on the
account — with it false, owner earnings are recorded internally as `PENDING`
(nothing is faked, nothing is transferred).

---

## Step 8 — Small real payment + verification

1. In the app, create a **cheap** booking (the amount is computed server-side
   from the booking row; the client cannot send an amount).
2. Pay with a real method. Checkout returns, the app calls
   `/api/payments/razorpay/verify`, and the webhook independently confirms.

Verify in the DB (read-only):

```bash
docker exec -it parkshare-db psql -U parkshare -d parkshare <<'SQL'
-- payment is SUCCESS, signature-verified and tagged live
SELECT payment_status, verification_status, razorpay_mode,
       razorpay_payment_id, amount_paise, paid_at
FROM payments ORDER BY created_at DESC LIMIT 3;

-- the booking moved to CONFIRMED
SELECT id, status, payment_status FROM bookings ORDER BY updated_at DESC LIMIT 3;

-- owner ledger row exists (PENDING when Route is off)
SELECT transfer_status, settlement_status, gross_amount_paise, owner_amount_paise
FROM payment_transfers ORDER BY created_at DESC LIMIT 3;

-- webhook was delivered and processed
SELECT event_type, processed_at FROM razorpay_webhook_events ORDER BY created_at DESC LIMIT 3;
SQL
```

Expected: `payments.payment_status = SUCCESS`, `verification_status` is
`SIGNATURE_VERIFIED` or `WEBHOOK_VERIFIED`, `razorpay_mode = live`, booking
`CONFIRMED`, one `payment_transfers` row, and a processed webhook event. Then
refund/settle per your own policy. Only a live-mode earning can be marked
settled; the test-mode row created during the phone test remains audit-only.

---

## Rollback (any step)

```bash
cd /opt/parkshare
# back to the previous (test) stack, no overlay
docker compose -f docker-compose.yml up -d
```

The overlay adds files only; the base compose is untouched, so removing the `-f
docker-compose.prod.yml` flag fully reverts routing. The `parkshare_uploads`
volume persists and is safe to keep.

---

## Known follow-ups (not blockers for the payment test)

1. **Rate limiter behind Traefik.** `clientIpOf()` prefers the socket peer
   address, which behind Traefik is the **Traefik container IP** — so all users
   share one bucket (e.g. the login limit becomes 30/min *globally*). Fine for
   launch, but worth a small code change later to trust `X-Forwarded-For` only
   from the known proxy. Traefik already appends it.
2. **Rotate any Razorpay key ever stored in plaintext or shared during the
   audit** (see the warning in Step 1).
3. **Single-instance rate limiting.** The limiter is in-process; if you ever run
   more than one backend replica it must move to a shared store.
4. **Uploads volume.** Confirm the overlay's `parkshare_uploads` is where you
   want photos to live; swap to object storage later without touching routes.

---

## Approval checklist

Before I finalize the `# REPLACE` values, I need the `inspect-vps.sh` output.
Before anything runs on the VPS, you confirm:

- [ ] external Traefik network name
- [ ] HTTPS entrypoint name + ACME certresolver name
- [ ] API domain / subdomain DNS already points at the VPS
- [ ] SMTP credentials not required (no OTP/email auth in ParkShare)
- [ ] Razorpay **test** key pair + a webhook secret created
- [ ] approval to run `up -d` with the overlay
