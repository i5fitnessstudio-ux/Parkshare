import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

/// Verifies that a user id still maps to a LIVE account.
///
/// Called on every authenticated request. The JWT signature alone only proves
/// the app issued the token once; without this check a token for an account
/// that has since been deactivated (or DELETED via self-service account
/// deletion) would keep working until it expired. Here the middleware asks
/// the database whether the account is still `is_active = TRUE` and
/// `deleted_at IS NULL`.
typedef ActiveUserVerifier = Future<bool> Function(String userId);

ActiveUserVerifier _activeUserVerifier = _checkActiveUserInDatabase;

/// Test seam: replaces the database-backed verifier. Every test that drives
/// [authMiddleware] / [requireUserId] / [authenticateAndBind] /
/// [requireUserIdOfRole] without a live pool MUST install a stub
/// (`setActiveUserVerifierForTesting((_) async => true)`), otherwise the
/// default verifier hits `Db.pool` and throws StateError.
void setActiveUserVerifierForTesting(ActiveUserVerifier verifier) {
  _activeUserVerifier = verifier;
}

/// Restores the production (database-backed) verifier after a test.
void resetActiveUserVerifier() {
  _activeUserVerifier = _checkActiveUserInDatabase;
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
  r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

Future<bool> _checkActiveUserInDatabase(String userId) async {
  // `users.id` is a UUID column; a malformed value can never come from a
  // token this app signed, so treat it as "no such live account".
  if (!_uuidPattern.hasMatch(userId)) return false;
  final res = await Db.pool.withConnection((conn) async {
    return conn.execute(
      Sql.named('''
      SELECT 1 FROM users
      WHERE id = @id AND is_active = TRUE AND deleted_at IS NULL
      '''),
      parameters: {'id': userId},
    );
  });
  return res.isNotEmpty;
}

/// Shared gate: an authenticated id that maps to a deactivated or deleted
/// account is refused with the SAME wording the login path uses, so a caller
/// cannot tell "deactivated" apart from "deleted" (no account-status oracle).
Future<void> _assertUserActive(String userId) async {
  final active = await _activeUserVerifier(userId);
  if (!active) {
    throw ApiError.forbidden('This account has been deactivated.');
  }
}

/// Bearer token auth middleware.
///
/// Verifies the JWT access token (HS256 only), then exposes:
///   request.context['userId']  - the authenticated user id
///   request.context['userRole'] - the authenticated user role
///
/// Order of checks matters (audit M-12 / route gating tests):
///   1. token validity (401)
///   2. role gate when [allowedRoles] is set (403, BEFORE the active check so
///      a user token still gets the dedicated role-403, never the
///      account-status 403)
///   3. the account must still be active / non-deleted (403)
Middleware authMiddleware({List<String> allowedRoles = const []}) {
  return (Handler inner) {
    return (Request request) async {
      final authHeader = request.headers['authorization'] ?? '';
      if (!authHeader.startsWith('Bearer ')) {
        throw ApiError.unauthorized('Missing access token.');
      }
      final token = authHeader.substring(7).trim();
      final payload = _verifyAccessToken(token);

      final userId = payload['sub'] as String?;
      final role = payload['role'] as String?;
      if (userId == null || role == null) {
        throw ApiError.unauthorized('Malformed access token.');
      }
      if (allowedRoles.isNotEmpty && !allowedRoles.contains(role)) {
        throw ApiError.forbidden('Access denied for role: $role.');
      }
      await _assertUserActive(userId);

      return inner(
        request.change(
          context: {...request.context, 'userId': userId, 'userRole': role},
        ),
      );
    };
  };
}

/// Verifies an access token, enforcing that the header algorithm is HS256
/// (preventing algorithm-confusion with `none` or asymmetric algorithms) and
/// that the token has not expired.
///
/// SECURITY (audit H-04): tokens used to carry no `exp` claim, so nothing here
/// could reject a stale token and a leak stayed valid forever. Tokens are now
/// issued with `iat`/`exp` and `JWT.verify` rejects an expired one. A token
/// that somehow still arrives without `exp` is refused outright rather than
/// being treated as infinitely valid.
Map<String, dynamic> _verifyAccessToken(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw ApiError.unauthorized('Malformed access token.');
  }
  try {
    final header = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
    ) as Map<String, dynamic>;
    final alg = header['alg'];
    if (alg != 'HS256') {
      throw ApiError.unauthorized('Unsupported token algorithm.');
    }
    // Also reject tokens carrying a `none` style algorithm.
    if (alg == 'none') {
      throw ApiError.unauthorized('Unsupported token algorithm.');
    }
  } catch (e) {
    if (e is ApiError) rethrow;
    throw ApiError.unauthorized('Malformed access token.');
  }

  try {
    final jwt = JWT.verify(token, SecretKey(Config.jwtSecret));
    final payload = jwt.payload;
    if (payload['type'] != 'access') {
      throw ApiError.unauthorized('Invalid token type.');
    }
    if (payload['exp'] is! num) {
      // Fail closed: an access token must state when it stops being valid.
      throw ApiError.unauthorized('Access token has no expiry.');
    }
    return payload;
  } on ApiError {
    rethrow;
  } on JWTException {
    throw ApiError.unauthorized('Invalid or expired access token.');
  } catch (_) {
    throw ApiError.unauthorized('Invalid or expired access token.');
  }
}

String userIdOf(Request request) => request.context['userId'] as String? ?? '';
String userRoleOf(Request request) =>
    request.context['userRole'] as String? ?? '';

/// Standalone auth for handlers that take shelf_router path parameters
/// (those handlers cannot be wrapped by [authMiddleware], which only accepts
/// single-argument Handlers). Verifies the Bearer token, checks that the
/// account is still active, and returns the authenticated user id; throws
/// [ApiError.unauthorized] otherwise.
///
/// IMPORTANT (audit M-12): this function only *returns* the identity — it does
/// NOT populate `request.context`. Callers that need the id must use the
/// return value. Reading `userIdOf(request)` after `requireUserId(request)`
/// silently yields `''`, which is how a `viewerId: ''` reached a service call.
Future<String> requireUserId(Request request) async {
  final authHeader = request.headers['authorization'] ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    throw ApiError.unauthorized('Missing access token.');
  }
  final payload = _verifyAccessToken(authHeader.substring(7).trim());
  final userId = payload['sub'] as String?;
  if (userId == null) {
    throw ApiError.unauthorized('Malformed access token.');
  }
  await _assertUserActive(userId);
  return userId;
}

/// Like [requireUserId] but also writes the identity into `request.context`, so
/// [userIdOf] / [userRoleOf] work for the handler too.
Future<Request> authenticateAndBind(Request request) async {
  final authHeader = request.headers['authorization'] ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    throw ApiError.unauthorized('Missing access token.');
  }
  final payload = _verifyAccessToken(authHeader.substring(7).trim());
  final userId = payload['sub'] as String?;
  final role = payload['role'] as String?;
  if (userId == null || role == null) {
    throw ApiError.unauthorized('Malformed access token.');
  }
  await _assertUserActive(userId);
  return request.change(
    context: {...request.context, 'userId': userId, 'userRole': role},
  );
}

/// Like [requireUserId] but additionally enforces roles (e.g. owner only).
Future<String> requireUserIdOfRole(
  Request request, {
  List<String> allowedRoles = const [],
}) async {
  final authHeader = request.headers['authorization'] ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    throw ApiError.unauthorized('Missing access token.');
  }
  final payload = _verifyAccessToken(authHeader.substring(7).trim());
  final userId = payload['sub'] as String?;
  final role = payload['role'] as String?;
  if (userId == null || role == null) {
    throw ApiError.unauthorized('Malformed access token.');
  }
  // Role first, active-check second: an under-privileged caller must get the
  // same dedicated 403 it always got, never the account-status message.
  if (allowedRoles.isNotEmpty && !allowedRoles.contains(role)) {
    throw ApiError.forbidden('Access denied for role: $role.');
  }
  await _assertUserActive(userId);
  return userId;
}