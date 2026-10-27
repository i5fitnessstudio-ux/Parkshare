import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/account_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Account routes:
///   DELETE /api/account
///
/// Self-service account deletion (vehicle user OR parking owner). The
/// identity always comes from the JWT via auth middleware — never from the
/// request body — and the password in the body re-authenticates the account
/// (bcrypt) so a stolen session cannot delete an account on its own.
///
/// SECURITY: the endpoint is rate-limited with the credential budget
/// ([Config.authRateLimitPerMinute]). The body is re-verified against the
/// stored hash, a wrong password answers 403 (NOT 401: a 401 would make
/// Flutter tear down the session mid-delete), and raw errors / SQL details
/// are never surfaced.
class AccountRoutes {
  final AccountService _service = AccountService();

  Handler get handler {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('Account route not found.');
      },
    );

    router.delete(
      '/',
      rateLimitMiddleware(
        requestsPerMinute: Config.authRateLimitPerMinute,
        name: 'account-delete',
      )(authMiddleware()((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final password = body['password']?.toString() ?? '';
        if (password.isEmpty) {
          throw ApiError.validation('password is required.');
        }
        await _service.deleteAccount(
          userId: userIdOf(req),
          password: password,
        );
        return ApiResponse.ok(null, AccountService.successMessage);
      })),
    );

    return router.call;
  }
}