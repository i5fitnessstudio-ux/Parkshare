// Manual (out-of-band) owner settlement regression tests.
//
// These are database-free, in the same style as the other payment tests: they
// drive the REAL router pipeline for the authorisation gate, and exercise the
// service's input validation (which runs BEFORE any SQL). The DB-backed state
// transitions (PENDING -> SETTLED, idempotency, owner totals moving) are
// exercised by integration testing against a disposable Postgres; see the
// migration/checklist rather than assuming a live DB in this process.
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/user.dart';
import 'package:parkshare_backend/routes/api_router.dart';
import 'package:parkshare_backend/services/admin_settlement_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

String token({required String role, String sub = 'test-user'}) {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return JWT({
    'sub': sub,
    'role': role,
    'type': 'access',
    'jti': 'manual-settlement-test',
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
      body: body ?? '{}',
      headers: {
        if (role != null)
          'authorization':
              'Bearer ${token(role: role, sub: sub ?? 'test-user')}',
      },
    ),
  );
}

void main() {
  // AUDIT ITEM 3: never depend on the developer's `backend/.env`.
  TestEnv.install();

  setUp(() => setActiveUserVerifierForTesting((_) async => true));
  tearDown(resetActiveUserVerifier);

  const admin = '11111111-1111-1111-1111-111111111111';
  const transfer = '22222222-2222-2222-2222-222222222222';
  const path = '/api/admin/settlements/$transfer/mark-settled';

  group('admin settlement route is ADMIN-only', () {
    test('401 without a token', () async {
      final res = await send('POST', path);
      expect(res.statusCode, 401);
    });

    test('403 for an OWNER token (owner cannot settle themselves)', () async {
      final res = await send('POST', path, role: 'owner', body: '{}');
      expect(res.statusCode, 403);
    });

    test('403 for a USER token', () async {
      final res = await send('POST', path, role: 'user', body: '{}');
      expect(res.statusCode, 403);
    });

    test('an ADMIN token passes the gate (reaches the service)', () async {
      final res = await send(
        'POST',
        path,
        role: 'admin',
        sub: admin,
        body: '{}',
      );
      // Anything other than 401/403 proves the gate opened. The service then
      // fails because no database pool is open in this test process.
      expect(res.statusCode, isNot(401));
      expect(res.statusCode, isNot(403));
    });

    test('401 for a garbage token', () async {
      final handler = const Pipeline()
          .addMiddleware(errorMiddleware())
          .addHandler(ApiRouter.create());
      final res = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost$path'),
          body: '{}',
          headers: {'authorization': 'Bearer garbage'},
        ),
      );
      expect(res.statusCode, 401);
    });

    test('the pending payout queue is ADMIN-only', () async {
      expect(
        (await send('GET', '/api/admin/settlements/pending')).statusCode,
        401,
      );
      expect(
        (await send(
          'GET',
          '/api/admin/settlements/pending',
          role: 'owner',
        )).statusCode,
        403,
      );
      final adminRes = await send(
        'GET',
        '/api/admin/settlements/pending',
        role: 'admin',
        sub: admin,
      );
      expect(adminRes.statusCode, isNot(401));
      expect(adminRes.statusCode, isNot(403));
    });

    test('the payout destination endpoint is ADMIN-only', () async {
      final destinationPath =
          '/api/admin/settlements/$transfer/payout-destination';
      expect((await send('GET', destinationPath)).statusCode, 401);
      expect(
        (await send('GET', destinationPath, role: 'user')).statusCode,
        403,
      );
      // Without a DB the service fails after the role gate; that is enough to
      // prove an admin is not blocked by the route.
      final adminRes = await send(
        'GET',
        destinationPath,
        role: 'admin',
        sub: admin,
      );
      expect(adminRes.statusCode, isNot(401));
      expect(adminRes.statusCode, isNot(403));
    });
  });

  group('admin role cannot be self-registered', () {
    test('UserRole.all (registerable) excludes admin', () {
      expect(UserRole.all.contains(UserRole.admin), isFalse);
      expect(UserRole.all, {UserRole.owner, UserRole.user});
    });

    test('admin is a known role', () {
      expect(UserRole.every.contains(UserRole.admin), isTrue);
    });
  });

  group('AdminSettlementService input validation (no DB)', () {
    final service = AdminSettlementService();

    Future<void> expectStatus(Future<Object?> future, int status) async {
      await expectLater(
        future,
        throwsA(
          isA<ApiError>().having((e) => e.statusCode, 'statusCode', status),
        ),
      );
    }

    test('empty transfer id is rejected as validation (400)', () async {
      await expectStatus(
        service.markSettled(transferId: '', adminUserId: admin),
        400,
      );
    });

    test('non-UUID transfer id is rejected as validation (400)', () async {
      await expectStatus(
        service.markSettled(transferId: 'not-a-uuid', adminUserId: admin),
        400,
      );
    });

    test('missing admin identity is rejected as unauthorized (401)', () async {
      await expectStatus(
        service.markSettled(transferId: transfer, adminUserId: ''),
        401,
      );
    });

    test('over-long payout reference is rejected (400)', () async {
      await expectStatus(
        service.markSettled(
          transferId: transfer,
          adminUserId: admin,
          reference: 'x' * 121,
        ),
        400,
      );
    });

    test('over-long note is rejected (400)', () async {
      await expectStatus(
        service.markSettled(
          transferId: transfer,
          adminUserId: admin,
          note: 'x' * 501,
        ),
        400,
      );
    });

    test(
      'payout destination validates its ids before touching the DB',
      () async {
        await expectStatus(
          service.getPayoutDestination(transferId: '', adminUserId: admin),
          400,
        );
        await expectStatus(
          service.getPayoutDestination(
            transferId: 'not-a-uuid',
            adminUserId: admin,
          ),
          400,
        );
        await expectStatus(
          service.getPayoutDestination(transferId: transfer, adminUserId: ''),
          401,
        );
      },
    );
  });

  group('SettlementStatus.isSettled', () {
    test('recognises SETTLED case-insensitively', () {
      expect(SettlementStatus.isSettled('SETTLED'), isTrue);
      expect(SettlementStatus.isSettled('settled'), isTrue);
      expect(SettlementStatus.isSettled(' SETTLED '), isTrue);
    });

    test('treats PENDING / null / unknown as not settled', () {
      expect(SettlementStatus.isSettled('PENDING'), isFalse);
      expect(SettlementStatus.isSettled(null), isFalse);
      expect(SettlementStatus.isSettled(''), isFalse);
      expect(SettlementStatus.isSettled('FAILED'), isFalse);
    });
  });

  group('SettlementStatus.isLiveRazorpayMode', () {
    test('only a live mode is settleable', () {
      expect(SettlementStatus.isLiveRazorpayMode('live'), isTrue);
      expect(SettlementStatus.isLiveRazorpayMode(' LIVE '), isTrue);
    });

    test('test, legacy-null and unknown modes are not settleable', () {
      expect(SettlementStatus.isLiveRazorpayMode('test'), isFalse);
      expect(SettlementStatus.isLiveRazorpayMode('TEST'), isFalse);
      expect(SettlementStatus.isLiveRazorpayMode(null), isFalse);
      expect(SettlementStatus.isLiveRazorpayMode(''), isFalse);
      expect(SettlementStatus.isLiveRazorpayMode('production'), isFalse);
    });
  });
}
