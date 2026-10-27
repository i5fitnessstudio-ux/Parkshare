// ignore_for_file: avoid_print
import 'dart:io' show Platform;

import 'package:dotenv/dotenv.dart';

/// Central application configuration loaded from the `.env` file
/// and process environment variables. Secrets are never hard-coded.
///
/// SECURITY (audit H-01 / H-02 / M-01 / M-16):
/// * [jwtSecret] no longer falls back to a *usable* secret when the
///   environment is `production`. In production a missing/weak
///   `JWT_SECRET` makes [validateForStartup] fail and `bin/server.dart`
///   exits BEFORE binding the socket, so a deployment can never silently
///   sign tokens with a key published in this repository.
/// * Password reset via OTP / email delivery is not part of the active
///   authentication flow, so no OTP is ever printed or returned and SMTP is
///   not required at startup.
class Config {
  Config._();

  /// The parsed `.env` file plus the process environment.
  ///
  /// Created lazily (rather than as a `static final`) so a test can install
  /// its overrides BEFORE the first configuration value is read.
  static DotEnv? _envInstance;

  static DotEnv get _env =>
      _envInstance ??= DotEnv(includePlatformEnvironment: true)..load();

  /// Test-only configuration overrides.
  ///
  /// Applied ON TOP of the `.env` file / process environment so `dart test`
  /// never depends on a developer's local `backend/.env`.
  ///
  /// SECURITY: only `test/support/test_env.dart` calls
  /// [applyTestOverrides]. `bin/server.dart` never does, and
  /// [validateForStartup] is completely untouched — a production boot is still
  /// validated against the real environment, exactly as before.
  static Map<String, String>? _testOverrides;

  /// Installs the test-only configuration overrides.
  ///
  /// TEST SUITES ONLY — never call this from application code.
  static void applyTestOverrides(Map<String, String> overrides) {
    _testOverrides = Map<String, String>.of(overrides);
  }

  /// Reads one configuration value.
  ///
  /// Test overrides win over the `.env` file; otherwise the `.env` file wins
  /// over the process environment (the `DotEnv` load order).
  static String? _get(String key) => _testOverrides?[key] ?? _env[key];

  /// The dev-only signing key. It is published in this repository, so it is
  /// usable ONLY while [isDevelopment] is true and is rejected outright by
  /// [validateForStartup] in production.
  static const String devJwtSecret = 'dev-only-insecure-secret-change-me';

  /// Development-only key material for the reversible encryption used by the
  /// owner payout details. Production MUST set a unique value; the published
  /// fallback is never used there (startup validation fails).
  static const String devOwnerPayoutEncryptionKey =
      'dev-only-owner-payout-encryption-key-change-me';

  /// Minimum length accepted for a production JWT secret (256 bits of entropy
  /// at minimum once base64/hex encoded).
  static const int minJwtSecretLength = 32;

  // ---------------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------------

  /// `APP_ENV` — `production` (default in hosted deployments) or anything
  /// else for development. Read with `_env` so `DotEnv(includePlatformEnvironment:
  /// true)` lets a platform variable override the `.env` file.
  static String get appEnv => (_get('APP_ENV') ?? 'development').trim();

  static bool get isProduction => appEnv.toLowerCase() == 'production';
  static bool get isDevelopment => !isProduction;

  /// When false (the default) the server prints no per-request access log and
  /// never dumps a stack trace.
  static bool get requestLoggingEnabled =>
      !isProduction || _bool('LOG_REQUESTS', false);

  /// Whether a failure may include the stack trace in the log output.
  static bool get verboseErrors => _bool('VERBOSE_ERRORS', !isProduction);

  static bool _bool(String key, bool fallback) {
    final raw = (_get(key) ?? '').trim().toLowerCase();
    if (raw.isEmpty) return fallback;
    return raw == 'true' || raw == '1' || raw == 'yes' || raw == 'on';
  }

  // ---------------------------------------------------------------------
  // Database
  // ---------------------------------------------------------------------

  static String get dbHost => _get('DB_HOST') ?? '127.0.0.1';
  static int get dbPort => int.tryParse(_get('DB_PORT') ?? '') ?? 5432;
  static String get dbName => _get('DB_NAME') ?? 'parkshare';
  static String get dbUser => _get('DB_USER') ?? 'parkshare';
  static String get dbPassword => _get('DB_PASSWORD') ?? '';

  /// HTTP port. Precedence: a test override, then the platform `PORT` env var
  /// (e.g. `$env:PORT=8081`), then `PORT` in backend/.env, then default 8080.
  static int get port =>
      int.tryParse(_testOverrides?['PORT'] ?? '') ??
      int.tryParse(Platform.environment['PORT'] ?? '') ??
      int.tryParse(_get('PORT') ?? '') ??
      8080;

  // ---------------------------------------------------------------------
  // JWT
  // ---------------------------------------------------------------------

  /// The HMAC signing key.
  ///
  /// In production there is NO fallback: a missing value yields an empty
  /// string, which [validateForStartup] rejects, so the process exits instead
  /// of running with a public key.
  static String get jwtSecret {
    final raw = (_get('JWT_SECRET') ?? '').trim();
    if (raw.isNotEmpty) return raw;
    return isProduction ? '' : devJwtSecret;
  }

  static int get accessExpiryMinutes =>
      int.tryParse(_get('JWT_ACCESS_EXPIRES_MINUTES') ?? '') ?? 60;
  static int get refreshTokenDays =>
      int.tryParse(_get('REFRESH_TOKEN_DAYS') ?? '') ?? 30;

  // ---------------------------------------------------------------------
  // Password policy (OTP/SMTP removed from active auth flow)
  // ---------------------------------------------------------------------

  /// Minimum length of a new password.
  static int get minPasswordLength =>
      int.tryParse(_get('MIN_PASSWORD_LENGTH') ?? '') ?? 8;

  /// Per-IP request budget for the unauthenticated auth endpoints, per
  /// minute. `0` disables the limiter (development only).
  static int get authRateLimitPerMinute =>
      int.tryParse(_get('AUTH_RATE_LIMIT_PER_MINUTE') ?? '') ?? 30;

  // ---------------------------------------------------------------------
  // CORS
  // ---------------------------------------------------------------------

  /// `CORS_ALLOWED_ORIGINS` — comma separated. Empty means "reflect nothing",
  /// and [allowedOrigins] then falls back to `*` in development only.
  static List<String> get corsAllowedOrigins {
    final raw = _get('CORS_ALLOWED_ORIGINS') ?? '';
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// The `Access-Control-Allow-Origin` values this server will ever send.
  static Set<String> get effectiveAllowedOrigins {
    final configured = corsAllowedOrigins;
    if (configured.isNotEmpty) return configured.toSet();
    if (isProduction) return const <String>{};
    return const <String>{'*'};
  }

  // ---------------------------------------------------------------------
  // Uploads / media storage
  // ---------------------------------------------------------------------

  /// Directory where owner parking photos are stored on disk. Never store
  /// absolute local device paths in PostgreSQL — the DB keeps public URLs.
  static String get uploadDir => _get('UPLOAD_DIR') ?? 'uploads';
  static int get maxUploadBytes =>
      int.tryParse(_get('MAX_UPLOAD_BYTES') ?? '') ?? (8 * 1024 * 1024);

  /// Public base URL for uploaded files, e.g. "https://api.parkshare.in".
  ///
  /// When empty the backend derives it from each request's Host header so the
  /// stored URL works for the Android emulator (10.0.2.2) and iOS simulator
  /// (localhost) during development. Production MUST set it — otherwise a
  /// caller can poison stored photo URLs with a spoofed `Host` header
  /// (audit M-03).
  static String get publicBaseUrl => (_get('PUBLIC_BASE_URL') ?? '').trim();

  // ---------------------------------------------------------------------
  // Razorpay (server-side secrets only; NEVER returned to the client)
  // ---------------------------------------------------------------------

  /// Public key id. This is the ONLY Razorpay value the app is ever given
  /// (via the create-order response), because Checkout needs it.
  static String get razorpayKeyId => (_get('RAZORPAY_KEY_ID') ?? '').trim();

  /// Secret used to sign orders and verify checkout signatures. Server only.
  static String get razorpayKeySecret =>
      (_get('RAZORPAY_KEY_SECRET') ?? '').trim();

  /// Secret used to verify the `X-Razorpay-Signature` webhook HMAC. Server only.
  static String get razorpayWebhookSecret =>
      (_get('RAZORPAY_WEBHOOK_SECRET') ?? '').trim();

  /// `test` by default. No behavioural branching on this value is required for
  /// the Payment Gateway; it exists for diagnostics/logging only.
  static String get razorpayMode =>
      (_get('RAZORPAY_MODE') ?? 'test').trim().toLowerCase();

  /// TRUE only when the ParkShare Razorpay account has Route enabled AND the
  /// owner linked-account onboarding is live. Defaults FALSE: the integration
  /// records owner earnings internally and calls NO transfer API.
  static bool get razorpayRouteEnabled =>
      _bool('RAZORPAY_ROUTE_ENABLED', false);

  /// ParkShare's marketplace commission, as a whole percent (0-100).
  /// Money math is done in integer paise in the payment service.
  static int get parkShareCommissionPercent {
    final raw =
        int.tryParse((_get('PARKSHARE_COMMISSION_PERCENT') ?? '').trim()) ?? 0;
    return raw.clamp(0, 100);
  }

  /// True when the server can create Razorpay orders (both key values set).
  static bool get razorpayConfigured =>
      razorpayKeyId.isNotEmpty && razorpayKeySecret.isNotEmpty;

  /// True when the webhook signature secret is present.
  static bool get razorpayWebhookConfigured => razorpayWebhookSecret.isNotEmpty;

  // ---------------------------------------------------------------------
  // Owner payouts (manual settlement while Route is unavailable)
  // ---------------------------------------------------------------------

  /// Secret used to encrypt owner bank account / IFSC at rest.
  ///
  /// The full settlement destination is needed to make a manual bank payout.
  /// It is stored AES-GCM encrypted, never in plaintext. Production has no
  /// usable fallback: a missing value makes [validateForStartup] fail.
  static String get ownerPayoutEncryptionKey {
    final raw = (_get('OWNER_PAYOUT_ENCRYPTION_KEY') ?? '').trim();
    if (raw.isNotEmpty) return raw;
    return isProduction ? '' : devOwnerPayoutEncryptionKey;
  }

  // ---------------------------------------------------------------------
  // Startup validation
  // ---------------------------------------------------------------------

  /// Returns a list of human-readable configuration problems. An empty list
  /// means the process may start. Called by `bin/server.dart` before the
  /// socket is bound so a misconfigured production deploy fails loudly
  /// instead of silently running insecurely.
  ///
  /// No secret value is ever included in the returned messages.
  static List<String> validateForStartup() {
    final problems = <String>[];

    final secret = jwtSecret;
    if (secret.isEmpty) {
      problems.add(
        'JWT_SECRET is not set. Add a random value of at least '
        '$minJwtSecretLength characters to backend/.env (or the process '
        'environment).',
      );
    } else if (isProduction) {
      if (secret == devJwtSecret) {
        problems.add(
          'JWT_SECRET is still the published development placeholder. '
          'Generate a unique secret, e.g. with: '
          r'$env:JWT_SECRET = [Convert]::ToBase64String('
          '[System.Security.Cryptography.RandomNumberGenerator]::GetBytes(48))',
        );
      } else if (secret.length < minJwtSecretLength) {
        problems.add(
          'JWT_SECRET is too short: $minJwtSecretLength characters minimum.',
        );
      }
    }

    // OTP/SMTP/email delivery not used by active ParkShare authentication.

    if (publicBaseUrl.isEmpty && isProduction) {
      problems.add(
        'PUBLIC_BASE_URL must be set in production so uploaded photo URLs '
        'cannot be poisoned through a spoofed Host header.',
      );
    }

    if (isProduction && effectiveAllowedOrigins.isEmpty) {
      problems.add(
        'CORS_ALLOWED_ORIGINS must list the origins allowed to call the API '
        'in production (comma separated).',
      );
    }

    // Razorpay: only validated when it is actually configured, so an existing
    // deployment that does not use online payments is completely unaffected.
    final razorpayKeyId = Config.razorpayKeyId;
    final razorpayKeySecret = Config.razorpayKeySecret;
    if (razorpayKeyId.isNotEmpty != razorpayKeySecret.isNotEmpty) {
      problems.add(
        'RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET must be set together.',
      );
    }
    // The mode is persisted per payment and decides whether its owner earning
    // may ever be settled. Refuse a typo instead of silently treating it as
    // test or live.
    if (razorpayConfigured) {
      final razorpayMode = Config.razorpayMode;
      if (razorpayMode != 'test' && razorpayMode != 'live') {
        problems.add(
          'RAZORPAY_MODE must be either "test" or "live" when Razorpay is '
          'configured.',
        );
      }
    }
    if (isProduction && razorpayConfigured && !razorpayWebhookConfigured) {
      problems.add(
        'RAZORPAY_WEBHOOK_SECRET must be set in production when Razorpay is '
        'enabled, otherwise webhooks cannot be authenticated.',
      );
    }

    // Owner payout details are reversible-encrypted at rest. A missing or
    // short key must stop a production boot: without it the saved bank details
    // cannot be protected, and silently starting would risk either data loss
    // or plaintext fallback.
    final payoutKey = ownerPayoutEncryptionKey;
    if (isProduction) {
      if (payoutKey.isEmpty) {
        problems.add(
          'OWNER_PAYOUT_ENCRYPTION_KEY is not set. Generate a random value of '
          'at least 32 characters and keep it stable: changing it makes '
          'previously saved payout details unreadable.',
        );
      } else if (payoutKey.length < 32) {
        problems.add(
          'OWNER_PAYOUT_ENCRYPTION_KEY is too short: 32 characters minimum.',
        );
      }
    }

    return problems;
  }

  static void load() {
    // Ensures Config is initialized (dotenv loaded) by touching properties.
    // NEVER prints a secret: only non-sensitive settings and booleans.
    print(
      'Config loaded: appEnv=$appEnv db=${dbHost}:${dbPort}/${dbName} '
      'port=$port uploads=${uploadDir} maxBytes=$maxUploadBytes '
      'corsOrigins=${effectiveAllowedOrigins.join(",")}',
    );
  }
}
