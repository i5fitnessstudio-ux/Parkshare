// Owner payment / settlement account regression tests.
//
// Split into two database-free layers:
//
//  1. Route gating — the owner payment-account endpoints are driven through the
//     REAL ApiRouter pipeline, so an unauthenticated caller or a vehicle user
//     is rejected *before* any SQL runs. This proves the owner-scoping at the
//     boundary (one owner can never address another owner's setup: there is no
//     ownerId in the path or body — it always comes from the JWT).
//
//  2. Validation + projection — OwnerPaymentAccountService rejects malformed
//     bank input with a 400 before it ever opens a connection, and the
//     owner-facing projection is a strict whitelist that can never carry a full
//     account number or IFSC.
//
// The DB-backed state machine (insert/update, pending settlement aggregation)
// is exercised by integration testing against a live Postgres, which this test
// process intentionally does not assume.
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/routes/api_router.dart';
import 'package:parkshare_backend/services/owner_payment_account_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

const String _validOwnerId = '11111111-1111-4111-8111-111111111111';

String token({required String role, String sub = _validOwnerId}) {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return JWT({
    'sub': sub,
    'role': role,
    'type': 'access',
    'jti': 'owner-payment-test',
    'iat': now,
    'exp': now + 3600,
  }).sign(SecretKey(Config.jwtSecret), algorithm: JWTAlgorithm.HS256);
}

Future<Response> send(
  String method,
  String path, {
  String? role,
  String? body,
}) async {
  final handler = const Pipeline()
      .addMiddleware(corsMiddleware())
      .addMiddleware(securityHeadersMiddleware())
      .addMiddleware(errorMiddleware())
      .addHandler(ApiRouter.create());

  return handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body,
      headers: {
        'content-type': 'application/json',
        if (role != null) 'authorization': 'Bearer ${token(role: role)}',
      },
    ),
  );
}

void main() {
  // AUDIT ITEM 3: never depend on the developer's `backend/.env`.
  TestEnv.install();

  setUp(() => setActiveUserVerifierForTesting((_) async => true));
  tearDown(resetActiveUserVerifier);

  group('owner payment-account route gating', () {
    test('GET without a token is 401 (never reaches the service)', () async {
      final res = await send('GET', '/api/payments/owner/payment-account');
      expect(res.statusCode, 401);
    });

    test('PUT without a token is 401', () async {
      final res = await send(
        'PUT',
        '/api/payments/owner/payment-account',
        body: '{}',
      );
      expect(res.statusCode, 401);
    });

    test('a vehicle user cannot read an owner payment account (403)', () async {
      final res = await send(
        'GET',
        '/api/payments/owner/payment-account',
        role: 'user',
      );
      expect(res.statusCode, 403);
    });

    test('a vehicle user cannot write an owner payment account (403)', () async {
      final res = await send(
        'PUT',
        '/api/payments/owner/payment-account',
        role: 'user',
        body: '{}',
      );
      expect(res.statusCode, 403);
    });

    test('an owner reaches the handler (validation error, not auth error) '
        'for a malformed body', () async {
      final res = await send(
        'PUT',
        '/api/payments/owner/payment-account',
        role: 'owner',
        body: jsonEncode(<String, dynamic>{'legalName': ''}),
      );
      // Auth passed; the service rejected the body before touching SQL.
      expect(res.statusCode, 400);
    });
  });

  group('OwnerPaymentAccountService validation (no DB)', () {
    final service = OwnerPaymentAccountService();

    Map<String, dynamic> validBody() => {
      'legalName': 'Poorani S',
      'accountType': 'INDIVIDUAL',
      'mobile': '9876543210',
      'email': 'poorani@example.com',
      'accountHolderName': 'Poorani S',
      'bankAccountNumber': '123456789012',
      'confirmBankAccountNumber': '123456789012',
      'ifscCode': 'HDFC0001234',
      'consent': true,
    };

    Future<void> expectRejected(
      Map<String, dynamic> body,
      String messageFragment,
    ) async {
      await expectLater(
        service.saveForOwner(ownerId: _validOwnerId, body: body),
        throwsA(
          isA<ApiError>().having(
            (e) => e.message,
            'message',
            contains(messageFragment),
          ),
        ),
      );
    }

    test('rejects a bank-account confirmation mismatch', () async {
      final body = validBody()..['confirmBankAccountNumber'] = '999999999999';
      await expectRejected(body, 'do not match');
    });

    test('rejects an invalid IFSC code', () async {
      final body = validBody()..['ifscCode'] = 'HDFC1234567';
      await expectRejected(body, 'IFSC');
    });

    test('rejects a too-short bank account number', () async {
      final body = validBody()..['bankAccountNumber'] = '12345';
      await expectRejected(body, 'account number');
    });

    test('rejects an invalid email', () async {
      final body = validBody()..['email'] = 'not-an-email';
      await expectRejected(body, 'email');
    });

    test('rejects an invalid mobile number', () async {
      final body = validBody()..['mobile'] = '12345';
      await expectRejected(body, 'mobile');
    });

    test('rejects a missing consent', () async {
      final body = validBody()..['consent'] = false;
      await expectRejected(body, 'settlement terms');
    });

    test('rejects an unknown account type', () async {
      final body = validBody()..['accountType'] = 'TRUST';
      await expectRejected(body, 'account type');
    });

    test('rejects an empty legal name', () async {
      final body = validBody()..['legalName'] = ' ';
      await expectRejected(body, 'name');
    });

    test('rejects a non-uuid owner id', () async {
      await expectLater(
        service.getForOwner(ownerId: 'not-a-uuid'),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('owner-facing projection is a strict whitelist', () {
    test('never carries a full account number or IFSC', () {
      final projection = OwnerPaymentAccountService.maskProjection(
        {
          'provider': 'RAZORPAY',
          'razorpay_onboarding_status': 'PENDING',
          'razorpay_settlement_enabled': false,
          'legal_name': 'Poorani S',
          'account_type': 'INDIVIDUAL',
          'account_holder_name': 'Poorani S',
          'bank_last4': '9012',
          // Adversarial extras that must NOT survive the projection.
          'bank_account_number': '123456789012',
          'ifsc_code': 'HDFC0001234',
          'razorpay_linked_account_id': 'acc_SECRET',
          'razorpay_key_secret': 'shhh',
        },
        ownerId: _validOwnerId,
      );

      expect(projection['bankLast4'], '9012');
      expect(projection['onboardingStatus'], 'PENDING');
      expect(projection['settlementEnabled'], isFalse);

      for (final leaked in const [
        'bank_account_number',
        'ifsc_code',
        'razorpay_linked_account_id',
        'razorpay_key_secret',
      ]) {
        expect(projection.containsKey(leaked), isFalse, reason: leaked);
      }
      expect(jsonEncode(projection), isNot(contains('123456789012')));
      expect(jsonEncode(projection), isNot(contains('HDFC0001234')));
      expect(jsonEncode(projection), isNot(contains('shhh')));
    });

    test('a missing row is an explicit NOT_STARTED shape', () {
      final projection = OwnerPaymentAccountService.maskProjection(
        null,
        ownerId: _validOwnerId,
      );
      expect(projection['onboardingStatus'], OnboardingStatus.notStarted);
      expect(projection['setupCompleted'], isFalse);
      expect(projection['settlementEnabled'], isFalse);
      expect(projection['bankLast4'], '');
    });
  });

  group('Route stays disabled by default', () {
    test('razorpayRouteEnabled is false unless explicitly enabled', () {
      // No RAZORPAY_ROUTE_ENABLED in the test environment: transfers must NOT
      // be attempted and settlement must stay PENDING.
      expect(Config.razorpayRouteEnabled, isFalse);
    });
  });
}
