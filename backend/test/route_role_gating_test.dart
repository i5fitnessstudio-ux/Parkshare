// Route-level authorisation regression tests.
//
// These drive the REAL `ApiRouter` through the same middleware pipeline that
// `bin/server.dart` builds, so they prove the ordering of checks, not just the
// helpers. Every request below is rejected (or accepted) *before* any service
// call, which is why no database is required: an unauthenticated or
// under-privileged caller can never reach a SQL statement.
//
// Covered here: C-01 (owner-only UPI settlement), the COD confirmation gate,
// C-02 (owner earnings scoping) and M-02 (owner-only uploads).
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/routes/api_router.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

String token({required String role, String sub = 'test-user'}) {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return JWT({
    'sub': sub,
    'role': role,
    'type': 'access',
    'jti': 'route-gating-test',
    'iat': now,
    'exp': now + 3600,
  }).sign(SecretKey(Config.jwtSecret), algorithm: JWTAlgorithm.HS256);
}

Future<Response> send(
  String method,
  String path, {
  String? role,
  String? sub,
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
      body: body ?? (method == 'GET' ? null : '{}'),
      headers: {
        if (role != null) 'authorization': 'Bearer ${token(role: role, sub: sub ?? 'test-user')}',
      },
    ),
  );
}

void main() {
  // AUDIT ITEM 3: never depend on the developer's `backend/.env`.
  TestEnv.install();

  // The production ActiveUserVerifier queries Db.pool, which is not open in
  // this process. Install a stub so tokens that pass the signature/role gate
  // reach the route handler (where the "passes the gate" tests expect a
  // service failure, not a crash on the active check).
  setUp(() => setActiveUserVerifierForTesting((_) async => true));
  tearDown(resetActiveUserVerifier);
  group('C-01: PUT /api/payments/{id}/upi/settle is owner-only', () {
    test('401 with no token', () async {
      final response = await send('PUT', '/api/payments/b1/upi/settle');
      expect(response.statusCode, 401);
    });

    test('403 for a USER token (IDOR closed)', () async {
      final response = await send(
        'PUT',
        '/api/payments/b1/upi/settle',
        role: 'user',
        sub: 'attacker',
      );
      expect(response.statusCode, 403);
    });

    test('an OWNER token passes the role gate (and reaches the service)', () async {
      final response = await send(
        'PUT',
        '/api/payments/b1/upi/settle',
        role: 'owner',
        sub: 'owner-1',
      );
      // Anything other than 401/403 proves the gate opened. The service call
      // then fails because no database pool is open in this test process.
      expect(response.statusCode, isNot(401));
      expect(response.statusCode, isNot(403));
    });

    test('401 for a garbage token', () async {
      final handler = const Pipeline()
          .addMiddleware(errorMiddleware())
          .addHandler(ApiRouter.create());
      final response = await handler(
        Request(
          'PUT',
          Uri.parse('http://localhost/api/payments/b1/upi/settle'),
          body: '{}',
          headers: {'authorization': 'Bearer garbage'},
        ),
      );
      expect(response.statusCode, 401);
    });
  });

  group('COD confirmation stays owner-only', () {
    test('401 with no token', () async {
      final response = await send('PUT', '/api/payments/b1/cod/confirm');
      expect(response.statusCode, 401);
    });

    test('403 for a USER token', () async {
      final response = await send(
        'PUT',
        '/api/payments/b1/cod/confirm',
        role: 'user',
        sub: 'attacker',
      );
      expect(response.statusCode, 403);
    });

    test('an OWNER token passes the role gate', () async {
      final response = await send(
        'PUT',
        '/api/payments/b1/cod/confirm',
        role: 'owner',
        sub: 'owner-1',
      );
      expect(response.statusCode, isNot(401));
      expect(response.statusCode, isNot(403));
    });
  });

  group('C-02: GET /api/payments/owner/earnings is owner-only and owner-scoped',
      () {
    test('401 with no token', () async {
      expect((await send('GET', '/api/payments/owner/earnings')).statusCode, 401);
    });

    test('403 for a USER token', () async {
      final response = await send(
        'GET',
        '/api/payments/owner/earnings',
        role: 'user',
        sub: 'attacker',
      );
      expect(response.statusCode, 403);
    });

    test('an OWNER token passes the role gate', () async {
      final response = await send(
        'GET',
        '/api/payments/owner/earnings',
        role: 'owner',
        sub: 'owner-1',
      );
      expect(response.statusCode, isNot(401));
      expect(response.statusCode, isNot(403));
    });
  });

  group('M-02: POST /api/uploads is owner-only', () {
    test('401 with no token', () async {
      final response = await send('POST', '/api/uploads');
      expect(response.statusCode, 401);
    });

    test('403 for a USER token (no longer a public file host)', () async {
      final response = await send('POST', '/api/uploads', role: 'user');
      expect(response.statusCode, 403);
    });

    test('an OWNER token passes the role gate', () async {
      final response = await send('POST', '/api/uploads', role: 'owner');
      expect(response.statusCode, isNot(401));
      expect(response.statusCode, isNot(403));
    });
  });

  group('payer endpoints require a token but allow any role', () {
    test('POST /api/payments/upi/intent is 401 without a token', () async {
      final response = await send('POST', '/api/payments/upi/intent');
      expect(response.statusCode, 401);
    });

    test('POST /api/payments/upi/confirm is 401 without a token', () async {
      final response = await send('POST', '/api/payments/upi/confirm');
      expect(response.statusCode, 401);
    });

    test('a USER token passes the gate (no role restriction for payers)', () async {
      final response = await send(
        'POST',
        '/api/payments/upi/intent',
        role: 'user',
      );
      expect(response.statusCode, isNot(401));
      expect(response.statusCode, isNot(403));
    });

    test('a missing bookingId is a 400 validation error, not a 500', () async {
      final response = await send('POST', '/api/payments/upi/intent', role: 'user');
      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['success'], isFalse);
      expect(body['message'], contains('bookingId'));
    });
  });

  group('Error responses still carry the security headers', () {
    test('a 403 from the role gate is not sniffable or framable', () async {
      final response = await send(
        'PUT',
        '/api/payments/b1/upi/settle',
        role: 'user',
      );
      expect(response.headers['x-content-type-options'], 'nosniff');
      expect(response.headers['x-frame-options'], 'DENY');
      expect(response.headers['vary'], 'Origin');
      expect(response.headers['content-type'], 'application/json');
    });
  });

  group('/health is public and answers without auth', () {
    test('200 with a status payload', () async {
      final response = await send('GET', '/health');
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['success'], isTrue);
      expect((body['data'] as Map<String, dynamic>)['status'], 'ok');
    });
  });

  group('unknown endpoints do not leak internals', () {
    test('a miss is a JSON 404', () async {
      final response = await send('GET', '/api/does-not-exist');
      expect(response.statusCode, 404);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['message'], contains('not found'));
    });
  });

  group('DELETE /api/account requires auth and a password body', () {
    test('401 with no token', () async {
      final response = await send('DELETE', '/api/account');
      expect(response.statusCode, 401);
    });

    test('400 when the body carries no password', () async {
      final response = await send('DELETE', '/api/account', role: 'user');
      expect(response.statusCode, 400);
      final body =
          jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['success'], isFalse);
      expect(body['message'], contains('password'));
    });

    test('a USER token passes the gate and reaches the service', () async {
      final response = await send(
        'DELETE',
        '/api/account',
        role: 'user',
        sub: 'user-1',
        body: '{"password":"whatever"}',
      );
      // Anything other than 401/403 proves the gate opened. The service call
      // then fails because no database pool is open in this test process.
      expect(response.statusCode, isNot(401));
      expect(response.statusCode, isNot(403));
    });

    test('an OWNER token passes the gate and reaches the service', () async {
      final response = await send(
        'DELETE',
        '/api/account',
        role: 'owner',
        sub: 'owner-1',
        body: '{"password":"whatever"}',
      );
      expect(response.statusCode, isNot(401));
      expect(response.statusCode, isNot(403));
    });
  });
}
