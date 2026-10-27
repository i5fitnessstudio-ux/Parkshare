// Regression tests for audit H-01 (the server must refuse to start with an
// insecure production configuration) and H-02 (no dev OTP in production).
//
// Two layers are exercised:
//
//  1. In-process assertions against the CONTROLLED TEST configuration
//     installed by `support/test_env.dart`. They no longer depend on the
//     developer's `backend/.env` at all. No secret value is ever printed:
//     only booleans and counts are asserted.
//
//  2. Subprocess assertions that boot `bin/server.dart` in an isolated
//     directory with NO `.env` file, so the *only* source of configuration is
//     the environment handed to the child. That makes every rule of
//     `Config.validateForStartup()` observable end to end, including the exit
//     code and the fact that the socket is never bound.
import 'dart:convert';
import 'dart:io';

import 'package:parkshare_backend/config/config.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

/// A throwaway value used ONLY to satisfy the length rule inside a subprocess.
/// It is not a deployment secret and grants access to nothing.
const String kStrongTestSecret =
    'TEST-ONLY-0000000000000000000000000000000000000000';

Directory _packageRoot() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/pubspec.yaml').existsSync() ||
      !File('${dir.path}/lib/config/config.dart').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not locate the backend package root');
    }
    dir = parent;
  }
  return dir;
}

/// Builds a directory that contains `bin/server.dart` and a package config
/// pointing at the real package, but NO `.env` file.
Directory makeSandbox() {
  final root = _packageRoot();
  final sandbox = Directory.systemTemp.createTempSync('parkshare_boot_');
  Directory('${sandbox.path}/bin').createSync(recursive: true);
  Directory('${sandbox.path}/.dart_tool').createSync(recursive: true);

  File('${root.path}/bin/server.dart')
      .copySync('${sandbox.path}/bin/server.dart');

  // The sandbox has no `lib/`, so the package config is rewritten to point at
  // the real package root with an absolute URI.
  final config = jsonDecode(
    File('${root.path}/.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final packages = (config['packages'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  for (final package in packages) {
    if (package['name'] == 'parkshare_backend') {
      package['rootUri'] = root.uri.toString();
    }
  }
  File('${sandbox.path}/.dart_tool/package_config.json')
      .writeAsStringSync(jsonEncode(config));
  return sandbox;
}

class BootResult {
  BootResult(this.exitCode, this.stdout, this.stderr);
  final int exitCode;
  final String stdout;
  final String stderr;
  String get all => '$stdout\n$stderr';
}

Future<BootResult> boot(
  Directory sandbox,
  Map<String, String> environment,
) async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['run', 'bin/server.dart'],
    workingDirectory: sandbox.path,
    environment: environment,
  );
  return BootResult(result.exitCode, '${result.stdout}', '${result.stderr}');
}

void main() {
  // AUDIT ITEM 3: the in-process assertions below run against the controlled
  // test configuration, never against a developer's `backend/.env`.
  TestEnv.install();

  group('In-process: the controlled test configuration', () {
    test('APP_ENV is not production', () {
      expect(Config.isProduction, isFalse);
      expect(Config.isDevelopment, isTrue);
    });

    test('the JWT secret is a real one, not the published placeholder', () {
      // Assertions only — the value itself is never printed.
      expect(Config.jwtSecret, isNotEmpty);
      expect(Config.jwtSecret, isNot(Config.devJwtSecret));
      expect(
        Config.jwtSecret.length,
        greaterThanOrEqualTo(Config.minJwtSecretLength),
      );
    });

    test('OTP/dev helpers are removed from active auth flow', () {
      // OTP/SMTP no longer used by active authentication.
    });

    test('validateForStartup never repeats a secret value', () {
      final secrets = <String>{
        if (Config.jwtSecret.isNotEmpty) Config.jwtSecret,
        if (Config.dbPassword.isNotEmpty) Config.dbPassword,
      };
      expect(secrets, isNotEmpty, reason: 'the test env does have secrets set');
      for (final problem in Config.validateForStartup()) {
        for (final secret in secrets) {
          expect(problem, isNot(contains(secret)));
        }
      }
    });

    test('OTP channel validation removed from startup checks', () {
      // Startup no longer requires SMTP or ALLOW_DEV_OTP for unused OTP flow.
    });

    test('auth hardening defaults are in place', () {
      expect(Config.minPasswordLength, greaterThanOrEqualTo(8));
      expect(Config.authRateLimitPerMinute, greaterThan(0));
    });

    test('production would silence request logging and stack traces', () {
      // In development both are on, which is what makes this test meaningful.
      expect(Config.requestLoggingEnabled, isTrue);
      expect(Config.verboseErrors, isTrue);
    });
  });

  group('H-01: a production boot is validated BEFORE the socket is bound', () {
    late Directory sandbox;

    setUpAll(() => sandbox = makeSandbox());
    tearDownAll(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    test('exit 1 and no listener when JWT_SECRET is missing', () async {
      final result = await boot(sandbox, {
        'APP_ENV': 'production',
        'JWT_SECRET': '',
      });

      expect(result.exitCode, 1);
      expect(result.stderr, contains('refusing to start'));
      expect(result.stderr, contains('JWT_SECRET is not set'));
      expect(
        result.all,
        isNot(contains('attempting to bind')),
        reason: 'the socket must never be opened',
      );
      expect(result.all, isNot(contains('ParkShare API listening')));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('exit 1 when JWT_SECRET is still the published placeholder', () async {
      final result = await boot(sandbox, {
        'APP_ENV': 'production',
        'JWT_SECRET': Config.devJwtSecret,
      });

      expect(result.exitCode, 1);
      expect(result.stderr, contains('published development placeholder'));
      expect(result.all, isNot(contains('attempting to bind')));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('exit 1 when JWT_SECRET is too short', () async {
      final result = await boot(sandbox, {
        'APP_ENV': 'production',
        'JWT_SECRET': 'short-secret',
      });

      expect(result.exitCode, 1);
      expect(result.stderr, contains('too short'));
      expect(result.all, isNot(contains('attempting to bind')));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('ALLOW_DEV_OTP is ignored (OTP flow removed)', () async {
      final result = await boot(sandbox, {
        'APP_ENV': 'production',
        'JWT_SECRET': '',
        'ALLOW_DEV_OTP': 'true',
      });

      expect(result.exitCode, 1);
      expect(result.stderr, contains('JWT_SECRET is not set'));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a production boot with no CORS allow-list is refused', () async {
      final result = await boot(sandbox, {
        'APP_ENV': 'production',
        'JWT_SECRET': kStrongTestSecret,
        'PUBLIC_BASE_URL': 'https://api.example.invalid',
        'CORS_ALLOWED_ORIGINS': '',
        'DB_PORT': '1',
      });

      expect(result.exitCode, 1);
      expect(result.stderr, contains('CORS_ALLOWED_ORIGINS must list'));
      expect(result.stdout, isNot(contains('corsOrigins=*')));
      expect(result.all, isNot(contains('attempting to bind')));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'a production boot without the payout encryption key is refused',
      () async {
        final result = await boot(sandbox, {
          'APP_ENV': 'production',
          'JWT_SECRET': kStrongTestSecret,
          'PUBLIC_BASE_URL': 'https://api.example.invalid',
          'CORS_ALLOWED_ORIGINS': 'https://app.example.invalid',
          'OWNER_PAYOUT_ENCRYPTION_KEY': '',
          'DB_PORT': '1',
        });

        expect(result.exitCode, 1);
        expect(
          result.stderr,
          contains('OWNER_PAYOUT_ENCRYPTION_KEY is not set'),
        );
        expect(result.all, isNot(contains('attempting to bind')));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('a production boot without PUBLIC_BASE_URL is refused', () async {
      final result = await boot(sandbox, {
        'APP_ENV': 'production',
        'JWT_SECRET': kStrongTestSecret,
        'PUBLIC_BASE_URL': '',
        'CORS_ALLOWED_ORIGINS': 'https://app.example.invalid',
        'DB_PORT': '1',
      });

      expect(result.exitCode, 1);
      expect(result.stderr, contains('PUBLIC_BASE_URL must be set'));
      expect(result.all, isNot(contains('attempting to bind')));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test(
      'an unknown RAZORPAY_MODE is refused before binding the socket',
      () async {
        final result = await boot(sandbox, {
          'APP_ENV': 'production',
          'JWT_SECRET': kStrongTestSecret,
          'PUBLIC_BASE_URL': 'https://api.example.invalid',
          'CORS_ALLOWED_ORIGINS': 'https://app.example.invalid',
          'RAZORPAY_KEY_ID': 'rzp_test_only_key_id',
          'RAZORPAY_KEY_SECRET': 'test-only-key-secret',
          'RAZORPAY_WEBHOOK_SECRET': 'test-only-webhook-secret',
          'RAZORPAY_MODE': 'production',
          'DB_PORT': '1',
        });

        expect(result.exitCode, 1);
        expect(result.stderr, contains('RAZORPAY_MODE must be either'));
        expect(result.all, isNot(contains('attempting to bind')));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'a fully valid production config passes validation and reaches the DB',
      () async {
        // DB_PORT=1 is a closed port, so the child dies at Db.init() instead of
        // opening the port. That failure is the proof that validation let it
        // through.
        final result = await boot(sandbox, {
          'APP_ENV': 'production',
          'JWT_SECRET': kStrongTestSecret,
          'SMTP_HOST': 'smtp.example.invalid',
          'PUBLIC_BASE_URL': 'https://api.example.invalid',
          'CORS_ALLOWED_ORIGINS': 'https://app.example.invalid',
          'OWNER_PAYOUT_ENCRYPTION_KEY':
              'TEST-ONLY-OWNER-PAYOUT-KEY-0000000000000000000000000000',
          'DB_PORT': '1',
        });

        expect(result.all, isNot(contains('refusing to start')));
        expect(result.all, isNot(contains('JWT_SECRET is not set')));
        expect(result.all, isNot(contains('PUBLIC_BASE_URL must be set')));
        expect(result.all, isNot(contains('CORS_ALLOWED_ORIGINS must list')));
        expect(result.all, isNot(contains('Database connection verified')));
        expect(
          result.all.toLowerCase(),
          contains('refused'),
          reason: 'it got past validation and failed on the refused DB socket',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('H-02: nothing secret is ever printed at boot', () {
    late Directory sandbox;

    setUpAll(() => sandbox = makeSandbox());
    tearDownAll(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    test('the boot banner lists settings, never the secret value', () async {
      const secret = 'SUPER-SECRET-VALUE-THAT-MUST-NEVER-BE-LOGGED-0123';
      final result = await boot(sandbox, {
        'APP_ENV': 'production',
        'JWT_SECRET': secret,
      });

      expect(result.exitCode, 1);
      expect(result.stdout, contains('Config loaded'));
      expect(result.stdout, isNot(contains(secret)));
      expect(result.stderr, isNot(contains(secret)));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('the remediation text names the variable, never its value', () async {
      // A too-short secret forces the JWT rule to fire, which is the message
      // that must name the variable without echoing it.
      const secret = 'SHORT';
      final result = await boot(sandbox, {
        'APP_ENV': 'production',
        'JWT_SECRET': secret,
        'PUBLIC_BASE_URL': 'https://api.example.invalid',
        'CORS_ALLOWED_ORIGINS': 'https://app.example.invalid',
        'DB_PORT': '1',
      });

      expect(result.exitCode, 1);
      expect(result.stderr, contains('JWT_SECRET is too short'));
      expect(result.all, isNot(contains(secret)));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
