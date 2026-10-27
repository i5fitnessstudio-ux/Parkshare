import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/razorpay_payment_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Public webhook routes.
///
/// These deliberately do NOT use user JWT auth: Razorpay authenticates itself
/// with an HMAC over the exact raw request body, using the
/// `X-Razorpay-Signature` header. The route reads the body as a STRING and
/// passes it unchanged to the verifier — re-encoding parsed JSON would change
/// the bytes and invalidate the signature.
///
///   POST /api/webhooks/razorpay
class WebhookRoutes {
  final RazorpayPaymentService _service = RazorpayPaymentService();

  Handler get handler {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('Webhook route not found.');
      },
    );

    router.post('/razorpay', (Request req) async {
      final rawBody = await req.readAsString();
      final signature = req.headers['x-razorpay-signature'] ?? '';
      final eventId = req.headers['x-razorpay-event-id'] ?? '';
      final result = await _service.processWebhook(
        rawBody: rawBody,
        signature: signature,
        eventIdFromHeader: eventId,
      );
      // 200 tells Razorpay not to retry. A bad signature throws before here
      // (mapped to 4xx by errorMiddleware) so Razorpay retries it, which is
      // harmless because processing is idempotent.
      return ApiResponse.ok(result, 'Webhook processed.');
    });

    return router.call;
  }
}
