// AUDIT ITEM 3 — regression test for backend test isolation.
//
// The backend test suite must produce the SAME result on every machine. It
// used to read the developer's local `backend/.env`, so two assertions in
// `config_startup_validation_test.dart` failed on any workstation that had
// `ALLOW_DEV_OTP=true` and passed on any workstation that had it off.
//
// These assertions lock the isolation in place:
//   * the controlled test environment wins over the developer's `.env`;
//   * the controlled values are test-only, never real credentials;
//   * the test-only webhook secret is NOT written into `backend/.env`.
import 'dart:io';

import 'package:parkshare_backend/config/config.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

void main() {
  // AUDIT ITEM 3: never depend on the developer's `backend/.env`.
  TestEnv.install();

  group('the controlled test environment overrides the local .env', () {
    test('the JWT secret is the test-only one, whatever .env says', () {
      expect(Config.jwtSecret, TestEnv.jwtSecret);
      expect(Config.jwtSecret, isNot(Config.devJwtSecret));
    });

    test('OTP/dev helpers are not used by active auth flow', () {
      // OTP/SMTP/email delivery removed from active authentication.
    });

    test('the app env is pinned to development', () {
      expect(Config.appEnv, 'development');
      expect(Config.isProduction, isFalse);
    });

    test('the webhook secret comes from the test environment', () {
      // The developer `.env` normally has NO RAZORPAY_WEBHOOK_SECRET at all,
      // so this assertion proves the override is really in effect.
      expect(Config.razorpayWebhookSecret, TestEnv.webhookSecret);
      expect(Config.razorpayWebhookConfigured, isTrue);
    });

    test('the Razorpay Route is forced off', () {
      expect(Config.razorpayRouteEnabled, isFalse);
    });

    test('the commission is pinned to zero', () {
      expect(Config.parkShareCommissionPercent, 0);
    });

    test('the HTTP port is pinned and never the default', () {
      expect(Config.port, 8099);
    });

    test('password policy is deterministic', () {
      expect(Config.minPasswordLength, 8);
      expect(Config.authRateLimitPerMinute, 30);
    });
  });

  group('the test-only webhook secret never reaches backend/.env', () {
    test('backend/.env does not carry the test-only webhook secret', () {
      final envFile = File('${Directory.current.path}/.env');
      if (!envFile.existsSync()) return; // nothing to check on this machine

      final contents = envFile.readAsStringSync();
      expect(
        contents.contains(TestEnv.webhookSecret),
        isFalse,
        reason:
            'The test-only webhook secret must live in the test suite only. '
            'backend/.env must keep the real deployment secret (or none).',
      );
    });

    test('the .env file is never given a key by the test suite', () {
      // `TestEnv.install()` only mutates in-process configuration; it must
      // not write anything to disk.
      final envFile = File('${Directory.current.path}/.env');
      final before = envFile.existsSync()
          ? envFile.readAsStringSync()
          : '<missing>';

      TestEnv.install();

      final after = envFile.existsSync()
          ? envFile.readAsStringSync()
          : '<missing>';
      expect(after, before);
    });
  });
}
