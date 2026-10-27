import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/vehicle_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Vehicle routes (Vehicle User's saved vehicles):
///   POST   /api/vehicles
///   GET    /api/vehicles
///   GET    /api/vehicles/{vehicleId}
///   PUT    /api/vehicles/{vehicleId}
///   DELETE /api/vehicles/{vehicleId}
class VehicleRoutes {
  final VehicleService _service = VehicleService();

  Handler get handler {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('Vehicle route not found.');
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
        return ApiResponse.created(payload, 'Vehicle saved.');
      }),
    );

    router.get(
      '/',
      authMiddleware()((Request req) async {
        final list = await _service.listByUser(userIdOf(req));
        return ApiResponse.ok({'vehicles': list}, 'Vehicles loaded.');
      }),
    );

    router.get('/<vehicleId>', (Request req, String vehicleId) async {
      final me = await requireUserId(req);
      final payload = await _service.getById(vehicleId, userId: me);
      return ApiResponse.ok(payload, 'Vehicle loaded.');
    });

    router.put('/<vehicleId>', (Request req, String vehicleId) async {
      final me = await requireUserId(req);
      final body = await readJsonBody(req) ?? {};
      final payload = await _service.update(
        id: vehicleId,
        userId: me,
        body: body,
      );
      return ApiResponse.ok(payload, 'Vehicle updated.');
    });

    router.delete('/<vehicleId>', (Request req, String vehicleId) async {
      final me = await requireUserId(req);
      await _service.delete(id: vehicleId, userId: me);
      return ApiResponse.ok(null, 'Vehicle deleted.');
    });

    return router.call;
  }
}
