import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/routes/account_routes.dart';
import 'package:parkshare_backend/routes/admin_routes.dart';
import 'package:parkshare_backend/routes/auth_routes.dart';
import 'package:parkshare_backend/routes/booking_routes.dart';
import 'package:parkshare_backend/routes/inbox_routes.dart';
import 'package:parkshare_backend/routes/parking_routes.dart';
import 'package:parkshare_backend/routes/payment_routes.dart';
import 'package:parkshare_backend/routes/upload_routes.dart';
import 'package:parkshare_backend/routes/vehicle_routes.dart';
import 'package:parkshare_backend/routes/webhook_routes.dart';
import 'package:parkshare_backend/storage/media_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Top-level API router. Mounts module routers under /api/.... and serves
/// uploaded parking photos from the local media storage under /uploads/....
class ApiRouter {
  static Handler create() {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('API endpoint not found.');
      },
    );

    router.mount('/api/auth', AuthRoutes().handler);
    router.mount('/api/account', AccountRoutes().handler);
    router.mount('/api/parkings', ParkingRoutes().handler);
    router.mount('/api/vehicles', VehicleRoutes().handler);
    router.mount('/api/bookings', BookingRoutes().handler);
    router.mount('/api/payments', PaymentRoutes().handler);
    router.mount('/api/admin', AdminRoutes().handler);
    router.mount('/api/webhooks', WebhookRoutes().handler);
    router.mount('/api/inbox', InboxRoutes().handler);
    router.mount('/api/uploads', UploadRoutes().handler);

    router.get('/health', (Request req) {
      return ApiResponse.ok({
        'status': 'ok',
        'time': DateTime.now().toIso8601String(),
      });
    });

    final apiHandler = router.call;
    final storage = LocalMediaStorage();

    return (Request request) async {
      // Serve uploaded photos before the router: /uploads/<file> -> file.
      if (request.url.path.startsWith('uploads/')) {
        return storage.serve(request);
      }
      return apiHandler(request);
    };
  }
}
