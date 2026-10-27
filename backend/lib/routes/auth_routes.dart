import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/auth_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Authentication routes:
///   POST /api/auth/register
///   POST /api/auth/login
///   POST /api/auth/refresh
///   GET  /api/auth/me
///   POST /api/auth/logout
///
/// OTP/password-reset via email delivery is not used by the active
/// ParkShare authentication flow.
class AuthRoutes {
  final AuthService _service = AuthService();

  Handler get handler {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('Auth route not found.');
      },
    );

    // Credential endpoints: the tighter budget, keyed per client address.
    final credentialLimit = rateLimitMiddleware(
      requestsPerMinute: Config.authRateLimitPerMinute,
      name: 'auth',
    );

    router.post(
      '/register',
      credentialLimit((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final payload = await _service.register(
          name: body['name']?.toString() ?? '',
          email: body['email']?.toString() ?? '',
          phone: body['phone']?.toString() ?? '',
          upiId: body['upiId']?.toString(),
          password: body['password']?.toString() ?? '',
          confirmPassword: body['confirmPassword']?.toString(),
          role: body['role']?.toString() ?? '',
        );
        return ApiResponse.created(
          payload.toJson(),
          'Account created successfully.',
        );
      }),
    );

    router.post(
      '/login',
      credentialLimit((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final payload = await _service.login(
          email: body['email']?.toString() ?? '',
          password: body['password']?.toString() ?? '',
          role: body['role']?.toString(),
        );
        return ApiResponse.ok(payload.toJson(), 'Login successful.');
      }),
    );

    router.post('/refresh', (Request req) async {
      final body = await readJsonBody(req) ?? {};
      final payload = await _service.refresh(
        body['refreshToken']?.toString() ?? '',
      );
      return ApiResponse.ok(payload.toJson(), 'Session refreshed.');
    });

    router.get(
      '/me',
      authMiddleware()((Request req) async {
        final payload = await _service.me(userIdOf(req));
        return ApiResponse.ok(payload.toJson(), 'User loaded.');
      }),
    );

    router.post('/logout', (Request req) async {
      final body = await readJsonBody(req) ?? {};
      await _service.logout(body['refreshToken']?.toString() ?? '');
      return ApiResponse.ok(null, 'Logged out successfully.');
    });

    // Password reset via OTP/email delivery is not used by the active
    // authentication flow. Endpoints intentionally omitted.

    return router.call;
  }
}
