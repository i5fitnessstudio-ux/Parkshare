import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/upload_service.dart';
import 'package:parkshare_backend/storage/media_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Upload routes:
///   POST /api/uploads  (multipart field "file"; JPG/PNG/WEBP photo only)
///
/// SECURITY (audit M-02): owner-only. The photos being uploaded are parking
/// listings, so a `user` account has no legitimate reason to call this. It was
/// previously open to any authenticated account, which turned the API into an
/// unmetered public file host.
class UploadRoutes {
  final UploadService _service = UploadService(LocalMediaStorage());

  Handler get handler {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('Upload route not found.');
      },
    );

    router.post(
      '/',
      authMiddleware(allowedRoles: ['owner'])((Request req) async {
        final payload = await _service.uploadImage(req);
        return ApiResponse.created(payload, 'Photo uploaded.');
      }),
    );

    return router.call;
  }
}
