// Regression tests for audit H-04 (JWT handling) and the role gate every
// owner-only endpoint depends on.
//
// Before the fix the middleware verified the signature with whatever algorithm
// the token's own header asked for and never required an `exp`, so:
//   * a token signed with the published dev key stayed valid forever;
//   * an `alg: none` / asymmetric-algorithm token was accepted;
//   * `JWT_ACCESS_EXPIRES_MINUTES` was reported to the client but not enforced.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

SecretKey get _secret => SecretKey(Config.jwtSecret);

int _nowSeconds() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

String signAccess({
  String sub = 'user-1',
  String role = 'user',
  String type = 'access',
  int? exp,
  bool includeExp = true,
}) {
  final payload = <String, dynamic>{
    'sub': sub,
    'role': role,
    'type': type,
    'jti': 'test-jti',
    'iat': _nowSeconds(),
    if (includeExp) 'exp': exp ?? (_nowSeconds() + 3600),
  };
  return JWT(payload).sign(_secret, algorithm: JWTAlgorithm.HS256);
}

/// Hand-crafts a token with an arbitrary JOSE header, bypassing [JWT.sign].
String tokenWithHeader(Map<String, dynamic> header, Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final signingInput = '${seg(header)}.${seg(payload)}';
  if (header['alg'] == 'none') return '$signingInput.';
  final hmac = Hmac(sha256, utf8.encode(Config.jwtSecret));
  final signature = base64Url
      .encode(hmac.convert(utf8.encode(signingInput)).bytes)
      .replaceAll('=', '');
  return '$signingInput.$signature';
}

Request makeRequest(String path, {String? token}) {
  return Request(
    'GET',
    Uri.parse('http://localhost$path'),
    headers: {
      if (token != null) 'authorization': 'Bearer $token',
    },
  );
}

/// Runs [handler] and returns the ApiError it threw, or null if it did not.
Future<ApiError?> captureError(Handler handler, Request request) async {
  try {
    await handler(request);
    return null;
  } on ApiError catch (e) {
    return e;
  }
}

void main() {
  // AUDIT ITEM 3: never depend on the developer's `backend/.env`.
  TestEnv.install();

  // The production ActiveUserVerifier hits Db.pool, which does not exist in
  // tests. Every test below that lets a token through signature verification
  // would otherwise crash on the DB check, so install a stub that treats every
  // account as live and restore the production verifier afterwards.
  setUp(() => setActiveUserVerifierForTesting((_) async => true));
  tearDown(resetActiveUserVerifier);

  group('H-04: access-token verification fails closed', () {
    test('the configured dev secret is not the published placeholder', () {
      expect(Config.jwtSecret, isNot(Config.devJwtSecret));
      expect(Config.jwtSecret.length, greaterThanOrEqualTo(32));
    });

    test('a valid access token is accepted and bound into the context', () async {
      Request? seen;
      final handler = authMiddleware()((Request req) {
        seen = req;
        return Response.ok('ok');
      });

      final response = await handler(
        makeRequest('/x', token: signAccess(sub: 'u-42', role: 'owner')),
      );

      expect(response.statusCode, 200);
      expect(seen, isNotNull);
      expect(userIdOf(seen!), 'u-42');
      expect(userRoleOf(seen!), 'owner');
    });

    test('a missing Authorization header is 401', () async {
      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        makeRequest('/x'),
      );
      expect(error?.statusCode, 401);
    });

    test('a non-Bearer scheme is 401', () async {
      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        Request(
          'GET',
          Uri.parse('http://localhost/x'),
          headers: {'authorization': 'Basic dXNlcjpwYXNz'},
        ),
      );
      expect(error?.statusCode, 401);
    });

    test('garbage is 401', () async {
      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        makeRequest('/x', token: 'not-a-jwt'),
      );
      expect(error?.statusCode, 401);
    });

    test('a token signed with a different key is 401', () async {
      final forged = JWT({
        'sub': 'admin',
        'role': 'owner',
        'type': 'access',
        'exp': _nowSeconds() + 3600,
      }).sign(SecretKey('some-other-signing-key'), algorithm: JWTAlgorithm.HS256);

      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        makeRequest('/x', token: forged),
      );
      expect(error?.statusCode, 401);
    });

    test('an EXPIRED token is 401 (expiry is finally enforced)', () async {
      final expired = signAccess(exp: _nowSeconds() - 60);
      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        makeRequest('/x', token: expired),
      );
      expect(error?.statusCode, 401);
    });

    test('a token with NO exp claim is refused, not treated as eternal', () async {
      final noExp = signAccess(includeExp: false);
      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        makeRequest('/x', token: noExp),
      );
      expect(error?.statusCode, 401);
      expect(error?.message, contains('expiry'));
    });

    test('a refresh token cannot be used as an access token', () async {
      final refresh = signAccess(type: 'refresh', exp: _nowSeconds() + 86400);
      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        makeRequest('/x', token: refresh),
      );
      expect(error?.statusCode, 401);
      expect(error?.message, contains('token type'));
    });

    // The guard is `alg != 'HS256'`, so both of these are refused before any
    // signature is even computed (algorithm-confusion defence).
    test('alg:none is rejected (algorithm confusion)', () async {
      final none = tokenWithHeader(
        {'alg': 'none', 'typ': 'JWT'},
        {
          'sub': 'admin',
          'role': 'owner',
          'type': 'access',
          'exp': _nowSeconds() + 3600,
        },
      );
      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        makeRequest('/x', token: none),
      );
      expect(error?.statusCode, 401);
      expect(error?.message, contains('algorithm'));
    });

    test('RS256 (asymmetric) is rejected outright', () async {
      final rs = tokenWithHeader(
        {'alg': 'RS256', 'typ': 'JWT'},
        {
          'sub': 'admin',
          'role': 'owner',
          'type': 'access',
          'exp': _nowSeconds() + 3600,
        },
      );
      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        makeRequest('/x', token: rs),
      );
      expect(error?.statusCode, 401);
      expect(error?.message, contains('algorithm'));
    });

    test('a token with no role claim is 401', () async {
      final noRole = JWT({
        'sub': 'u-1',
        'type': 'access',
        'exp': _nowSeconds() + 3600,
      }).sign(_secret, algorithm: JWTAlgorithm.HS256);

      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        makeRequest('/x', token: noRole),
      );
      expect(error?.statusCode, 401);
      expect(error?.message, contains('Malformed'));
    });
  });

  group('Role gate: a USER token is 403 on owner-only endpoints', () {
    test('authMiddleware(allowedRoles: ["owner"]) rejects a user token', () async {
      var reached = false;
      final handler = authMiddleware(allowedRoles: ['owner'])((_) {
        reached = true;
        return Response.ok('should not happen');
      });

      final error = await captureError(
        handler,
        makeRequest('/x', token: signAccess(role: 'user')),
      );

      expect(error?.statusCode, 403);
      expect(reached, isFalse, reason: 'the handler must never run');
    });

    test('an owner token passes the owner-only gate', () async {
      var reached = false;
      final handler = authMiddleware(allowedRoles: ['owner'])((_) {
        reached = true;
        return Response.ok('ok');
      });

      final response = await handler(
        makeRequest('/x', token: signAccess(role: 'owner')),
      );

      expect(response.statusCode, 200);
      expect(reached, isTrue);
    });

    test('an empty allow-list means "any authenticated role"', () async {
      final handler = authMiddleware()((_) => Response.ok('ok'));
      for (final role in ['user', 'owner', 'admin']) {
        final response = await handler(
          makeRequest('/x', token: signAccess(role: role)),
        );
        expect(response.statusCode, 200, reason: role);
      }
    });

    test('an unknown role is 403 on an owner-only route', () async {
      final error = await captureError(
        authMiddleware(allowedRoles: ['owner'])((_) => Response.ok('ok')),
        makeRequest('/x', token: signAccess(role: 'superuser')),
      );
      expect(error?.statusCode, 403);
    });
  });

  group('M-12: requireUserId returns the identity (not an empty string)', () {
    test('returns the subject of a valid token', () async {
      final request = makeRequest('/x', token: signAccess(sub: 'u-77'));
      expect(await requireUserId(request), 'u-77');
    });

    test('throws 401 without a token', () async {
      await expectLater(
        requireUserId(makeRequest('/x')),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 401)),
      );
    });

    test('requireUserIdOfRole enforces the role and returns the id', () async {
      final owner = makeRequest('/x', token: signAccess(sub: 'o-9', role: 'owner'));
      expect(await requireUserIdOfRole(owner, allowedRoles: ['owner']), 'o-9');

      final user = makeRequest('/x', token: signAccess(sub: 'u-9', role: 'user'));
      await expectLater(
        requireUserIdOfRole(user, allowedRoles: ['owner']),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 403)),
      );
    });

    test('authenticateAndBind populates userIdOf/userRoleOf', () async {
      final bound = await authenticateAndBind(
        makeRequest('/x', token: signAccess(sub: 'u-5', role: 'owner')),
      );
      expect(userIdOf(bound), 'u-5');
      expect(userRoleOf(bound), 'owner');
    });

    test('authenticateAndBind throws 401 without a token', () async {
      await expectLater(
        authenticateAndBind(makeRequest('/x')),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'status', 401)),
      );
    });
  });

  group('DS: tokens of deactivated/deleted accounts are refused', () {
    test('authMiddleware answers 403 with the deactivation wording', () async {
      setActiveUserVerifierForTesting((_) async => false);

      final error = await captureError(
        authMiddleware()((_) => Response.ok('ok')),
        makeRequest('/x', token: signAccess(sub: 'gone-1')),
      );

      expect(error?.statusCode, 403);
      expect(error?.message, 'This account has been deactivated.');
    });

    test('requireUserId answers 403 for an inactive/deleted account', () async {
      setActiveUserVerifierForTesting((_) async => false);

      await expectLater(
        requireUserId(makeRequest('/x', token: signAccess(sub: 'gone-2'))),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'status', 403)
              .having(
                (e) => e.message,
                'message',
                'This account has been deactivated.',
              ),
        ),
      );
    });

    test('the role gate runs BEFORE the active check (dedicated 403)',
        () async {
      // A user token on an owner-only route must keep getting the role 403
      // even when the account is inactive, never the account-status message.
      setActiveUserVerifierForTesting((_) async => false);

      final error = await captureError(
        authMiddleware(allowedRoles: ['owner'])((_) => Response.ok('ok')),
        makeRequest('/x', token: signAccess(role: 'user')),
      );

      expect(error?.statusCode, 403);
      expect(error?.message, contains('Access denied for role'));
    });

    test('requireUserIdOfRole checks the role first, then active', () async {
      setActiveUserVerifierForTesting((_) async => false);

      final owner = makeRequest('/x', token: signAccess(sub: 'o-7', role: 'owner'));
      await expectLater(
        requireUserIdOfRole(owner, allowedRoles: ['owner']),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'status', 403)
              .having(
                (e) => e.message,
                'message',
                'This account has been deactivated.',
              ),
        ),
      );

      final user = makeRequest('/x', token: signAccess(sub: 'u-7', role: 'user'));
      await expectLater(
        requireUserIdOfRole(user, allowedRoles: ['owner']),
        throwsA(
          isA<ApiError>()
              .having((e) => e.statusCode, 'status', 403)
              .having((e) => e.message, 'message', contains('Access denied')),
        ),
      );
    });
  });

  group('401 responses carry the challenge header', () {
    test('ApiError.unauthorized sets www-authenticate', () {
      expect(
        ApiError.unauthorized().responseHeaders['www-authenticate'],
        'Bearer realm="parkshare"',
      );
    });

    test('a 403 does not leak the realm', () {
      expect(ApiError.forbidden().responseHeaders.containsKey('www-authenticate'), isFalse);
    });
  });
}
