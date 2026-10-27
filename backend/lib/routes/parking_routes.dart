import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/booking_service.dart';
import 'package:parkshare_backend/services/parking_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Parking routes:
///   POST   /api/parkings
///   GET    /api/parkings/nearby?lat=&lng=&radiusKm=&vehicleId=&startDate=&endDate=
///   GET    /api/parkings/owner/{ownerId}
///   GET    /api/parkings/{parkingId}?vehicleId=&startDate=&endDate=
///   GET    /api/parkings/{parkingId}/spaces
///   GET    /api/parkings/{parkingId}/availability?startDate=&endDate=&vehicleId=
///   PUT    /api/parkings/{parkingId}
///   DELETE /api/parkings/{parkingId}
class ParkingRoutes {
  final ParkingService _service = ParkingService();
  final BookingService _bookingService = BookingService();

  /// Optional `YYYY-MM-DD` query parameter. An unparseable value is treated as
  /// absent rather than a 400, so a stale client link still works.
  static DateTime? _dateParam(Map<String, String> q, String key) =>
      DateTime.tryParse(q[key] ?? '');

  Handler get handler {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('Parking route not found.');
      },
    );

    router.post(
      '/',
      authMiddleware(allowedRoles: ['owner'])((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final payload = await _service.create(
          ownerId: userIdOf(req),
          body: body,
        );
        return ApiResponse.created(payload, 'Parking listing published.');
      }),
    );

    router.get(
      '/nearby',
      authMiddleware()((Request req) async {
        final q = req.url.queryParameters;
        final lat = double.tryParse(q['lat'] ?? '');
        final lng = double.tryParse(q['lng'] ?? '');
        final radiusKm = double.tryParse(q['radiusKm'] ?? '') ?? 5;
        if (lat == null || lng == null) {
          throw ApiError.validation(
            'lat and lng query parameters are required.',
          );
        }
        // Slot-aware search: with a vehicle selected the response carries a
        // per-parking `availability` block (free slots that actually fit),
        // without one the map just shows the listings.
        final vehicleId = (q['vehicleId'] ?? '').trim();
        final list = await _service.nearby(
          lat: lat,
          lng: lng,
          radiusKm: radiusKm,
          vehicleId: vehicleId.isEmpty ? null : vehicleId,
          startDate: _dateParam(q, 'startDate'),
          endDate: _dateParam(q, 'endDate'),
        );
        return ApiResponse.ok({'parkings': list}, 'Nearby parking loaded.');
      }),
    );

    router.get('/owner/<ownerId>', (Request req, String ownerId) async {
      final me = await requireUserId(req);
      if (me != ownerId) {
        throw ApiError.forbidden('You can only list your own parking.');
      }
      final list = await _service.listByOwner(ownerId);
      return ApiResponse.ok({'parkings': list}, 'Parking listings loaded.');
    });

    router.get('/<parkingId>', (Request req, String parkingId) async {
      // AUDIT M-12: use the id requireUserId *returns*. The old code called
      // requireUserId(req) and threw the result away, then read
      // userIdOf(req) — which is '' because requireUserId never writes the
      // request context — so the service was always called with an anonymous
      // viewer.
      final viewerId = await requireUserId(req);
      final q = req.url.queryParameters;
      final vehicleId = (q['vehicleId'] ?? '').trim();
      final payload = await _service.getById(
        parkingId,
        viewerId: viewerId,
        vehicleId: vehicleId.isEmpty ? null : vehicleId,
        startDate: _dateParam(q, 'startDate'),
        endDate: _dateParam(q, 'endDate'),
      );
      return ApiResponse.ok(payload, 'Parking listing loaded.');
    });

    /// The individual physical spaces of a listing (C1, C2, B1 …) with their
    /// live availability for the requested window.
    router.get(
      '/<parkingId>/spaces',
      authMiddleware()((Request req) async {
        final segments = req.url.pathSegments;
        if (segments.length < 2) {
          throw ApiError.validation('parkingId is required.');
        }
        final parkingId = segments[segments.length - 2];
        final q = req.url.queryParameters;
        final start = _dateParam(q, 'startDate');
        final end = _dateParam(q, 'endDate');
        final vehicleId = (q['vehicleId'] ?? '').trim();
        final payload = await _service.spaces(
          parkingId,
          vehicleId: vehicleId.isEmpty ? null : vehicleId,
          startDate: start,
          endDate: end,
        );
        return ApiResponse.ok(payload, 'Parking spaces loaded.');
      }),
    );

    // Date-window availability probe. UX only — BookingService.create()
    // remains the authoritative 409 guard against double bookings.
    router.get(
      '/<parkingId>/availability',
      authMiddleware()((Request req) async {
        // Mounted under /api/parkings, so the inner path is
        // "<parkingId>/availability" — the id is the second-to-last segment
        // (".last" would be the literal "availability").
        final segments = req.url.pathSegments;
        if (segments.length < 2) {
          throw ApiError.validation('parkingId is required.');
        }
        final parkingId = segments[segments.length - 2];
        final q = req.url.queryParameters;
        final start = DateTime.tryParse(q['startDate'] ?? '');
        final end = DateTime.tryParse(q['endDate'] ?? '');
        if (start == null || end == null) {
          throw ApiError.validation(
            'startDate and endDate query parameters are required '
            '(YYYY-MM-DD).',
          );
        }
        final vehicleId = (q['vehicleId'] ?? '').trim();
        final vehicleType = (q['vehicleType'] ?? '').trim();
        final payload = await _bookingService.availability(
          parkingId: parkingId,
          startDate: start,
          endDate: end,
          vehicleId: vehicleId.isEmpty ? null : vehicleId,
          vehicleType: vehicleType.isEmpty ? null : vehicleType,
        );
        return ApiResponse.ok(payload, 'Availability checked.');
      }),
    );

    router.put('/<parkingId>', (Request req, String parkingId) async {
      final ownerId = await requireUserIdOfRole(req, allowedRoles: ['owner']);
      final body = await readJsonBody(req) ?? {};
      final payload = await _service.update(
        parkingId: parkingId,
        ownerId: ownerId,
        body: body,
      );
      return ApiResponse.ok(payload, 'Parking listing updated.');
    });

    router.delete('/<parkingId>', (Request req, String parkingId) async {
      final ownerId = await requireUserIdOfRole(req, allowedRoles: ['owner']);
      await _service.delete(parkingId: parkingId, ownerId: ownerId);
      return ApiResponse.ok(null, 'Parking listing deleted.');
    });

    return router.call;
  }
}
