import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/booking_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Booking routes:
///   POST /api/bookings
///   GET  /api/bookings/owner/{ownerId}
///   GET  /api/bookings/user/{userId}
///   GET  /api/bookings/{bookingId}
///   PUT  /api/bookings/{bookingId}/accept
///   PUT  /api/bookings/{bookingId}/reject
class BookingRoutes {
  final BookingService _service = BookingService();

  Handler get handler {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('Booking route not found.');
      },
    );

    router.post(
      '/',
      authMiddleware()((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final payload = await _service.create(
          userId: userIdOf(req),
          body: body,
        );
        return ApiResponse.created(payload, 'Booking requested.');
      }),
    );

    router.get('/owner/<ownerId>', (Request req, String ownerId) async {
      final me = await requireUserId(req);
      if (me != ownerId) {
        throw ApiError.forbidden('You can only list your own bookings.');
      }
      final list = await _service.listByOwner(ownerId);
      return ApiResponse.ok({'bookings': list}, 'Bookings loaded.');
    });

    router.get('/user/<userId>', (Request req, String userId) async {
      final me = await requireUserId(req);
      if (me != userId) {
        throw ApiError.forbidden('You can only list your own bookings.');
      }
      final list = await _service.listByUser(userId);
      return ApiResponse.ok({'bookings': list}, 'Bookings loaded.');
    });

    router.get('/<bookingId>', (Request req, String bookingId) async {
      final me = await requireUserId(req);
      final payload = await _service.getById(bookingId, viewerId: me);
      return ApiResponse.ok(payload, 'Booking loaded.');
    });

    router.put('/<bookingId>/accept', (Request req, String bookingId) async {
      final ownerId = await requireUserIdOfRole(req, allowedRoles: ['owner']);
      final payload = await _service.accept(
        bookingId: bookingId,
        ownerId: ownerId,
      );
      return ApiResponse.ok(payload, 'Booking accepted.');
    });

    router.put('/<bookingId>/reject', (Request req, String bookingId) async {
      final ownerId = await requireUserIdOfRole(req, allowedRoles: ['owner']);
      final payload = await _service.reject(
        bookingId: bookingId,
        ownerId: ownerId,
      );
      return ApiResponse.ok(payload, 'Booking rejected.');
    });

    return router.call;
  }
}
