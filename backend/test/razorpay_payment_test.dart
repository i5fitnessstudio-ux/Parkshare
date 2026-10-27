// Razorpay payment regression tests.
//
// These are pure, database-free tests: they cover the security-critical
// primitives (checkout + webhook HMAC verification, constant-time compare,
// integer money) and the route-level authentication gate on the two new
// endpoints. The DB-backed state machine (create order / mark paid / owner
// earning once) is exercised by integration testing against a live Postgres,
// which this test process intentionally does not assume.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/routes/api_router.dart';
import 'package:parkshare_backend/services/razorpay_payment_service.dart';
import 'package:parkshare_backend/services/razorpay_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

String token({required String role, String sub = 'test-user'}) {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return JWT({
    'sub': sub,
    'role': role,
    'type': 'access',
    'jti': 'razorpay-test',
    'iat': now,
    'exp': now + 3600,
  }).sign(SecretKey(Config.jwtSecret), algorithm: JWTAlgorithm.HS256);
}

Future<Response> send(
  String method,
  String path, {
  String? role,
  String? body,
  Map<String, String> extraHeaders = const {},
}) async {
  final handler = const Pipeline()
      .addMiddleware(corsMiddleware())
      .addMiddleware(securityHeadersMiddleware())
      .addMiddleware(errorMiddleware())
      .addHandler(ApiRouter.create());
  return await handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body ?? '{}',
      headers: {
        if (role != null) 'authorization': 'Bearer ${token(role: role)}',
        ...extraHeaders,
      },
    ),
  );
}

void main() {
  // AUDIT ITEM 3: never depend on the developer's `backend/.env`.
  TestEnv.install();

  setUp(() => setActiveUserVerifierForTesting((_) async => true));
  tearDown(resetActiveUserVerifier);

  group('checkout signature verification', () {
    // Vector: HMAC_SHA256("order_test_123|pay_test_456", "test_secret_key").
    const orderId = 'order_test_123';
    const paymentId = 'pay_test_456';
    const secret = 'test_secret_key';
    const validSignature =
        'ecbb8338a392433ea04780a5be4a1e5c1d0a263fc8b29ab3cee472375e0214b2';

    test('accepts the correct signature', () {
      expect(
        RazorpayService.verifyCheckoutSignature(
          orderId: orderId,
          paymentId: paymentId,
          signature: validSignature,
          secret: secret,
        ),
        isTrue,
      );
    });

    test('rejects a tampered signature', () {
      final tampered = '${validSignature.substring(0, 63)}0';
      expect(
        RazorpayService.verifyCheckoutSignature(
          orderId: orderId,
          paymentId: paymentId,
          signature: tampered,
          secret: secret,
        ),
        isFalse,
      );
    });

    test('rejects when the order id does not match the signed message', () {
      expect(
        RazorpayService.verifyCheckoutSignature(
          orderId: 'order_other',
          paymentId: paymentId,
          signature: validSignature,
          secret: secret,
        ),
        isFalse,
      );
    });

    test('rejects empty inputs', () {
      expect(
        RazorpayService.verifyCheckoutSignature(
          orderId: '',
          paymentId: paymentId,
          signature: validSignature,
          secret: secret,
        ),
        isFalse,
      );
      expect(
        RazorpayService.verifyCheckoutSignature(
          orderId: orderId,
          paymentId: paymentId,
          signature: '',
          secret: secret,
        ),
        isFalse,
      );
    });

    test('rejects a non-hex signature instead of throwing', () {
      expect(
        RazorpayService.verifyCheckoutSignature(
          orderId: orderId,
          paymentId: paymentId,
          signature: 'not-hex!!',
          secret: secret,
        ),
        isFalse,
      );
    });
  });

  group('webhook signature verification', () {
    const rawBody = '{"event":"payment.captured"}';
    const secret = 'whsec_test_secret';
    const validSignature =
        'e5fa4af2825f2f0153e20fe54892da0757c269be918d9ede705ccb272de19cae';

    test('accepts the correct HMAC over the exact raw body', () {
      expect(
        RazorpayService.verifyWebhookSignature(
          rawBody: rawBody,
          signature: validSignature,
          secret: secret,
        ),
        isTrue,
      );
    });

    test(
      'rejects when the body is re-encoded (signature must be over bytes)',
      () {
        // Same JSON, different byte sequence (extra space) => different HMAC.
        expect(
          RazorpayService.verifyWebhookSignature(
            rawBody: '{"event": "payment.captured"}',
            signature: validSignature,
            secret: secret,
          ),
          isFalse,
        );
      },
    );

    test('rejects an invalid signature', () {
      expect(
        RazorpayService.verifyWebhookSignature(
          rawBody: rawBody,
          signature: 'deadbeef',
          secret: secret,
        ),
        isFalse,
      );
    });

    test('rejects when no webhook secret is configured', () {
      expect(
        RazorpayService.verifyWebhookSignature(
          rawBody: rawBody,
          signature: validSignature,
          secret: '',
        ),
        isFalse,
      );
    });
  });

  group('constant-time comparison', () {
    test('equal byte lists match', () {
      expect(RazorpayService.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('different lengths do not match', () {
      expect(RazorpayService.constantTimeEquals([1, 2, 3], [1, 2]), isFalse);
    });

    test('single differing byte does not match', () {
      expect(RazorpayService.constantTimeEquals([1, 2, 3], [1, 9, 3]), isFalse);
    });
  });

  group('money is integer paise', () {
    test('₹500.00 is 50000 paise', () {
      expect(rupeesToPaise(500.0), 50000);
    });

    test('₹1 is 100 paise', () {
      expect(rupeesToPaise(1.0), 100);
    });

    test('fractional rupees round to the nearest paise, never a double', () {
      expect(rupeesToPaise(499.99), 49999);
      expect(rupeesToPaise(0.1), 10);
    });

    test('rowPaise reads the integer column and defaults safely', () {
      expect(rowPaise({'amount_paise': 50000}), 50000);
      expect(rowPaise({'amount_paise': null}), 0);
      expect(rowPaise({}), 0);
    });
  });

  group('RazorpayOrder parsing', () {
    test('maps the Razorpay order payload', () {
      final order = RazorpayOrder.fromJson({
        'id': 'order_abc',
        'amount': 50000,
        'currency': 'INR',
        'receipt': 'ps_booking1',
        'status': 'created',
      });
      expect(order.id, 'order_abc');
      expect(order.amountPaise, 50000);
      expect(order.currency, 'INR');
    });
  });

  group('route authentication gate', () {
    test('POST /api/payments/razorpay/order requires auth', () async {
      final response = await send('POST', '/api/payments/razorpay/order');
      expect(response.statusCode, 401);
    });

    test('POST /api/payments/razorpay/verify requires auth', () async {
      final response = await send('POST', '/api/payments/razorpay/verify');
      expect(response.statusCode, 401);
    });

    test('an authenticated user passes the gate on /razorpay/order', () async {
      final response = await send(
        'POST',
        '/api/payments/razorpay/order',
        role: 'user',
        body: '{"bookingId":"b1"}',
      );
      // Not 401/403 proves the gate opened; the service then fails because no
      // database pool is open in this test process.
      expect(response.statusCode, isNot(401));
      expect(response.statusCode, isNot(403));
    });

    test('the webhook route is reachable WITHOUT a user JWT', () async {
      // The controlled test environment configures a webhook secret, so the
      // request is refused (400, invalid signature) rather than demanding a
      // JWT (401). That proves Razorpay can call it unauthenticated and the
      // HMAC is the only gate.
      final response = await send(
        'POST',
        '/api/webhooks/razorpay',
        body: '{"event":"payment.captured"}',
      );
      expect(response.statusCode, isNot(401));
    });
  });

  group('webhook route enforces the HMAC gate', () {
    const rawBody = '{"event":"payment.captured"}';

    /// Builds the exact `X-Razorpay-Signature` for [rawBody] using the
    /// TEST-ONLY webhook secret from the controlled test environment.
    String sign(String body) {
      final mac = Hmac(sha256, utf8.encode(TestEnv.webhookSecret));
      return mac
          .convert(utf8.encode(body))
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    }

    test('the test environment does configure a webhook secret', () {
      expect(Config.razorpayWebhookConfigured, isTrue);
      expect(Config.razorpayWebhookSecret, TestEnv.webhookSecret);
    });

    test('a wrong signature is rejected with 400', () async {
      final response = await send(
        'POST',
        '/api/webhooks/razorpay',
        body: rawBody,
        extraHeaders: {'x-razorpay-signature': 'deadbeefdeadbeef'},
      );
      expect(response.statusCode, 400);
      expect(await response.readAsString(), contains('Invalid webhook signature'));
    });

    test('a missing signature is rejected with 400', () async {
      final response = await send('POST', '/api/webhooks/razorpay', body: rawBody);
      expect(response.statusCode, 400);
      expect(await response.readAsString(), contains('Invalid webhook signature'));
    });

    test('a signature over different bytes is rejected with 400', () async {
      // The HMAC is over the EXACT raw body; re-encoding the JSON changes the
      // bytes and must therefore fail.
      final response = await send(
        'POST',
        '/api/webhooks/razorpay',
        body: '{"event": "payment.captured"}',
        extraHeaders: {'x-razorpay-signature': sign(rawBody)},
      );
      expect(response.statusCode, 400);
      expect(await response.readAsString(), contains('Invalid webhook signature'));
    });

    test('a correct signature passes the HMAC gate', () async {
      final response = await send(
        'POST',
        '/api/webhooks/razorpay',
        body: rawBody,
        extraHeaders: {'x-razorpay-signature': sign(rawBody)},
      );
      // NOT 400 proves the HMAC was accepted. The request then fails in the
      // database layer (there is no pool in this test process), which is
      // exactly the proof that the webhook was never rejected as unverified.
      expect(response.statusCode, isNot(400));
      expect(response.statusCode, isNot(401));
      expect(response.statusCode, isNot(403));
      expect(response.statusCode, isNot(503));
    });
  });

  group('webhook body parsing is defensive', () {
    test('a valid HMAC built at test-time matches (sanity)', () {
      final mac = Hmac(sha256, utf8.encode('s'));
      final hex = mac
          .convert(utf8.encode('m'))
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(
        RazorpayService.verifyWebhookSignature(
          rawBody: 'm',
          signature: hex,
          secret: 's',
        ),
        isTrue,
      );
    });
  });
}
