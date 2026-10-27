// Controlled test environment for the backend test suite.
//
// WHY THIS EXISTS
// ---------------
// AUDIT ITEM 3: the backend tests must never depend on a developer's local
// `backend/.env`. Before this file existed, two assertions in
// `config_startup_validation_test.dart` failed on any machine whose `.env`
// had `ALLOW_DEV_OTP=true` (and passed on any machine that had it off), i.e.
// the test result depended on the developer's workstation, not on the code.
//
// The fix is a deterministic, explicitly-listed configuration that is applied
// ON TOP of the `.env` file / process environment by
// [Config.applyTestOverrides]. Every value below is a test-only value:
//
//   * it is NOT a real credential of any kind,
//   * it grants access to nothing,
//   * it is never written to `backend/.env`,
//   * it never reaches a production deployment (production reads the real
//     environment; `Config.validateForStartup()` is completely untouched).
//
// SECURITY: the Razorpay webhook secret below is a TEST-ONLY value. It exists
// so the webhook route can be exercised with a real HMAC in a test, without
// ever placing a fake secret into `backend/.env` and without weakening the
// production startup rule that requires `RAZORPAY_WEBHOOK_SECRET` to be set.
import 'package:parkshare_backend/config/config.dart';

/// The controlled configuration used by every backend test.
class TestEnv {
  TestEnv._();

  /// A fixed, test-only JWT signing key.
  ///
  /// It is long enough to satisfy the production length rule and it is NOT
  /// [Config.devJwtSecret], so the "never sign with the published
  /// placeholder" assertion stays meaningful.
  static const String jwtSecret =
      'TEST-ONLY-JWT-SECRET-FOR-BACKEND-TESTS-NEVER-USE-IN-PRODUCTION-01';

  /// A fixed, test-only Razorpay key id.
  static const String razorpayKeyId = 'rzp_test_only_key_id';

  /// A fixed, test-only Razorpay key secret.
  static const String razorpayKeySecret = 'test-only-key-secret';

  /// A fixed, test-only Razorpay webhook secret.
  ///
  /// TEST-ONLY. It is deliberately NOT written to `backend/.env`: the file
  /// must keep whatever the real deployment provides, and the production
  /// startup validation must keep failing when the webhook secret is missing.
  static const String webhookSecret = 'test-only-webhook-secret';

  /// Fixed test-only key for reversible encryption of payout bank details.
  static const String ownerPayoutEncryptionKey =
      'TEST-ONLY-OWNER-PAYOUT-ENCRYPTION-KEY-NEVER-USE-IN-PRODUCTION-01';

  /// The complete, explicit configuration for the test process.
  ///
  /// Every key [Config] reads is listed here, so nothing can leak in from a
  /// developer's `.env`.
  static const Map<String, String> values = <String, String>{
    // --- environment ---------------------------------------------------
    // Development, so the production-only startup rules are NOT what the
    // in-process assertions exercise; those are covered by the subprocess
    // boot tests in `config_startup_validation_test.dart`.
    'APP_ENV': 'development',
    'LOG_REQUESTS': 'true',
    'VERBOSE_ERRORS': 'true',

    // --- database (never connected to in the unit tests) ----------------
    'DB_HOST': '127.0.0.1',
    'DB_PORT': '5432',
    'DB_NAME': 'parkshare_test',
    'DB_USER': 'parkshare_test',
    'DB_PASSWORD': 'test-only-db-password',

    // --- http -----------------------------------------------------------
    // A port that is not the default 8080, so a test can never collide with
    // a locally running server.
    'PORT': '8099',

    // --- jwt ------------------------------------------------------------
    'JWT_SECRET': jwtSecret,
    'JWT_ACCESS_EXPIRES_MINUTES': '60',
    'REFRESH_TOKEN_DAYS': '30',

    // --- password policy -----------------------------------------------
    'MIN_PASSWORD_LENGTH': '8',
    'AUTH_RATE_LIMIT_PER_MINUTE': '30',

    // --- cors ------------------------------------------------------------
    // Empty => the development wildcard applies, which is what the CORS
    // regression tests in `middleware_test.dart` expect.
    'CORS_ALLOWED_ORIGINS': '',

    // --- uploads ---------------------------------------------------------
    'UPLOAD_DIR': 'test-uploads',
    'MAX_UPLOAD_BYTES': '8388608',
    'PUBLIC_BASE_URL': 'http://localhost:8099',

    // --- razorpay (test mode, route disabled) ----------------------------
    'RAZORPAY_KEY_ID': razorpayKeyId,
    'RAZORPAY_KEY_SECRET': razorpayKeySecret,
    'RAZORPAY_WEBHOOK_SECRET': webhookSecret,
    'RAZORPAY_MODE': 'test',
    // Route stays OFF: the integration records owner earnings internally and
    // never calls a transfer API.
    'RAZORPAY_ROUTE_ENABLED': 'false',
    'PARKSHARE_COMMISSION_PERCENT': '0',

    // --- owner payouts ---------------------------------------------------
    // Manual settlement stores the bank destination encrypted at rest. Test
    // runs must use a deterministic key or a round-trip would fail.
    'OWNER_PAYOUT_ENCRYPTION_KEY': ownerPayoutEncryptionKey,
  };

  /// Installs the controlled configuration for the current test process.
  ///
  /// Call this as the first statement of `main()` in every test file that
  /// reads [Config]. Each `dart test` file runs in its own isolate, so the
  /// override never leaks between suites.
  static void install() {
    Config.applyTestOverrides(values);
  }
}
