import 'dart:convert';

import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/services/owner_payment_account_service.dart';
import 'package:parkshare_backend/services/payment_service.dart';
import 'package:parkshare_backend/services/razorpay_payment_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Payment routes (UPI + Cash on Delivery + Razorpay):
///   GET  /api/payments/parking/{parkingId}/owner   owner UPI + contact info
///   POST /api/payments/upi/intent                  create the pending UPI payment
///   POST /api/payments/upi/confirm                 claim submitted -> PENDING
///                                                   VERIFICATION (NOT verified)
///   POST /api/payments/upi/fail                    UPI cancelled/failed
///   POST /api/payments/cod                         COD_PENDING booking
///   PUT  /api/payments/{bookingId}/cod/confirm     owner marks cash received
///   PUT  /api/payments/{bookingId}/upi/settle      owner verifies a UPI payment
///   POST /api/payments/razorpay/order              server-authoritative order
///   POST /api/payments/razorpay/verify             verify Checkout signature
///   GET  /api/payments/owner/earnings             server-computed owner totals
///   GET  /api/payments/owner/payment-account      owner settlement account
///   PUT  /api/payments/owner/payment-account      save owner settlement setup
///   POST /api/payments                             legacy combined endpoint
///
/// SECURITY (audit C-01): `/upi/confirm` is NOT a "payment succeeded"
/// endpoint. It records the payer's declaration and answers 202 with an
/// explicit `paymentVerification` block. It can never produce a `SUCCESS`
/// payment, a booking in `CONFIRMED`, or an invented transaction id — those
/// require the owner attestation in `/upi/settle` (or a verified Razorpay
/// signature / webhook).
///
/// The Razorpay routes never accept an authoritative amount or linked-account
/// id from the client: the amount is read from the booking row and the owner
/// account from `owner_payment_accounts`.
class PaymentRoutes {
  final PaymentService _service = PaymentService();
  final RazorpayPaymentService _razorpay = RazorpayPaymentService();
  final OwnerPaymentAccountService _ownerAccounts =
      OwnerPaymentAccountService();

  Handler get handler {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('Payment route not found.');
      },
    );

    // ---- Owner payment info for the selected parking ------------------
    router.get('/parking/<parkingId>/owner', (
      Request req,
      String parkingId,
    ) async {
      // Auth-only gate: the caller id is deliberately not used here, so the
      // value returned by requireUserId is not needed.
      await requireUserId(req);
      final payload = await _service.ownerPaymentInfo(parkingId);
      return ApiResponse.ok(payload, 'Owner payment details loaded.');
    });

    // ---- UPI ----------------------------------------------------------
    router.post(
      '/upi/intent',
      authMiddleware()((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final bookingId = body['bookingId']?.toString() ?? '';
        if (bookingId.isEmpty) {
          throw ApiError.validation('bookingId is required.');
        }
        final payload = await _service.createUpiIntent(
          bookingId: bookingId,
          userId: userIdOf(req),
        );
        return ApiResponse.created(payload, 'UPI payment started.');
      }),
    );

    router.post(
      '/upi/confirm',
      authMiddleware()((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final bookingId = body['bookingId']?.toString() ?? '';
        if (bookingId.isEmpty) {
          throw ApiError.validation('bookingId is required.');
        }
        final raw = body['rawResponse'];
        final payload = await _service.confirmUpi(
          bookingId: bookingId,
          userId: userIdOf(req),
          transactionId: body['transactionId']?.toString(),
          reference: body['reference']?.toString(),
          rawResponse: raw is Map<String, dynamic> ? raw : null,
        );
        // 202 Accepted: the declaration was recorded, the payment is NOT
        // verified. A 200 here would invite clients to render "paid".
        return Response(
          202,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'success': true,
            'message': kUpiUnverifiedMessage,
            'data': payload,
          }),
        );
      }),
    );

    router.post(
      '/upi/fail',
      authMiddleware()((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final bookingId = body['bookingId']?.toString() ?? '';
        if (bookingId.isEmpty) {
          throw ApiError.validation('bookingId is required.');
        }
        final payload = await _service.failUpi(
          bookingId: bookingId,
          userId: userIdOf(req),
          reason: body['reason']?.toString(),
        );
        return ApiResponse.ok(payload, 'Payment was not completed.');
      }),
    );

    // ---- COD ----------------------------------------------------------
    router.post(
      '/cod',
      authMiddleware()((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final bookingId = body['bookingId']?.toString() ?? '';
        if (bookingId.isEmpty) {
          throw ApiError.validation('bookingId is required.');
        }
        final payload = await _service.createCod(
          bookingId: bookingId,
          userId: userIdOf(req),
        );
        return ApiResponse.created(
          payload,
          'Please contact your parking owner to pay cash.',
        );
      }),
    );

    // Owner marks the cash received -> booking CONFIRMED + earnings updated.
    router.put('/<bookingId>/cod/confirm', (
      Request req,
      String bookingId,
    ) async {
      final ownerId = await requireUserIdOfRole(req, allowedRoles: ['owner']);
      final payload = await _service.confirmCod(
        bookingId: bookingId,
        ownerId: ownerId,
      );
      return ApiResponse.ok(payload, 'Cash payment confirmed.');
    });

    // Owner verifies the UPI credit they can see in their own account ->
    // payment SUCCESS + booking CONFIRMED + earnings updated (once).
    router.put('/<bookingId>/upi/settle', (
      Request req,
      String bookingId,
    ) async {
      final ownerId = await requireUserIdOfRole(req, allowedRoles: ['owner']);
      final payload = await _service.settleUpi(
        bookingId: bookingId,
        ownerId: ownerId,
      );
      return ApiResponse.ok(payload, 'UPI payment verified and confirmed.');
    });

    // ---- Owner settlement totals (server-computed) ---------------------
    // AUDIT C-02: the dashboard used to sum `amount` client-side over whatever
    // page of bookings it had loaded. This endpoint is the authoritative figure
    // and always scoped to the authenticated owner.
    router.get('/owner/earnings', (Request req) async {
      final ownerId = await requireUserIdOfRole(req, allowedRoles: ['owner']);
      final payload = await _service.ownerEarningsSummary(ownerId: ownerId);
      return ApiResponse.ok(payload, 'Owner earnings loaded.');
    });

    // ---- Owner payment / settlement account ----------------------------
    // The owner id always comes from the verified JWT (requireUserIdOfRole),
    // NEVER from the request body — so one owner can never read or edit
    // another's setup. The response is a masked projection: no full account
    // number, no IFSC, no provider secret, no linked-account id.
    router.get('/owner/payment-account', (Request req) async {
      final ownerId = await requireUserIdOfRole(req, allowedRoles: ['owner']);
      final payload = await _ownerAccounts.getForOwner(ownerId: ownerId);
      return ApiResponse.ok(payload, 'Payment account loaded.');
    });

    // Registers the owner's settlement details and records the setup locally as
    // PENDING (Razorpay Route onboarding is not faked). The full destination is
    // AES-256-GCM encrypted; the response exposes only bank_last4.
    router.put('/owner/payment-account', (Request req) async {
      final ownerId = await requireUserIdOfRole(req, allowedRoles: ['owner']);
      final body = await readJsonBody(req) ?? {};
      final payload = await _ownerAccounts.saveForOwner(
        ownerId: ownerId,
        body: body,
      );
      return ApiResponse.ok(payload, 'Payment account saved.');
    });

    // The same save is also accepted as POST, matching the "POST or PUT"
    // convention used elsewhere for create-or-update.
    router.post('/owner/payment-account', (Request req) async {
      final ownerId = await requireUserIdOfRole(req, allowedRoles: ['owner']);
      final body = await readJsonBody(req) ?? {};
      final payload = await _ownerAccounts.saveForOwner(
        ownerId: ownerId,
        body: body,
      );
      return ApiResponse.ok(payload, 'Payment account saved.');
    });

    // ---- Razorpay online payment ---------------------------------------
    // Creates a server-authoritative order for the booking. The amount is
    // derived from `bookings.amount`; any client amount is ignored. Only the
    // public key id is returned (never the key secret).
    router.post(
      '/razorpay/order',
      authMiddleware()((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final bookingId = body['bookingId']?.toString() ?? '';
        if (bookingId.isEmpty) {
          throw ApiError.validation('bookingId is required.');
        }
        final payload = await _razorpay.createOrder(
          bookingId: bookingId,
          userId: userIdOf(req),
        );
        return ApiResponse.created(payload, 'Payment order created.');
      }),
    );

    // Verifies the Checkout callback signature and, only then, marks the
    // booking paid. Idempotent: repeating a valid callback is a no-op.
    router.post(
      '/razorpay/verify',
      authMiddleware()((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final bookingId = body['bookingId']?.toString() ?? '';
        final orderId = body['razorpayOrderId']?.toString() ?? '';
        final paymentId = body['razorpayPaymentId']?.toString() ?? '';
        final signature = body['razorpaySignature']?.toString() ?? '';
        if (bookingId.isEmpty) {
          throw ApiError.validation('bookingId is required.');
        }
        final payload = await _razorpay.verifyCheckout(
          bookingId: bookingId,
          userId: userIdOf(req),
          razorpayOrderId: orderId,
          razorpayPaymentId: paymentId,
          razorpaySignature: signature,
        );
        return ApiResponse.ok(payload, 'Payment verified.');
      }),
    );

    // ---- Legacy combined endpoint (kept for older clients) -------------
    router.post(
      '/',
      authMiddleware()((Request req) async {
        final body = await readJsonBody(req) ?? {};
        final payload = await _service.create(
          userId: userIdOf(req),
          body: body,
        );
        return ApiResponse.created(
          payload,
          'Payment request recorded and awaiting verification.',
        );
      }),
    );

    return router.call;
  }
}
