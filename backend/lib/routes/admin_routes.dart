import 'dart:convert';

import 'package:parkshare_backend/middleware/auth_middleware.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/user.dart';
import 'package:parkshare_backend/services/admin_settlement_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// Back-office (admin-only) routes. No Flutter surface reaches these.
///
///   GET  /api/admin/settlements/pending
///   GET  /api/admin/settlements/{paymentTransferId}/payout-destination
///   POST /api/admin/settlements/{paymentTransferId}/mark-settled
///
/// AUTHORITY: the acting admin id comes from the verified JWT only
/// ([requireUserIdOfRole] with role `admin`). The owner being paid is derived
/// by the service from the `payment_transfers` row itself — the request body
/// can neither name an owner nor a payout amount.
///
/// This is the TEMPORARY manual settlement path used while Razorpay Route is
/// not activated. It records a payout ParkShare already made outside Razorpay;
/// it never calls Razorpay and never creates a transfer id.
class AdminRoutes {
  final AdminSettlementService _settlements = AdminSettlementService();

  Handler get handler {
    final router = Router(
      notFoundHandler: (Request req) {
        return ApiResponse.notFound('Admin route not found.');
      },
    );

    // Queue of live earnings that still need a manual payout. Test-mode rows
    // are excluded by the service, not by the caller.
    router.get('/settlements/pending', (Request req) async {
      await requireUserIdOfRole(req, allowedRoles: [UserRole.admin]);
      final limit = int.tryParse(req.url.queryParameters['limit'] ?? '');
      final rows = await _settlements.listPending(limit: limit ?? 100);
      return ApiResponse.ok(rows, 'Pending settlements loaded.');
    });

    // Full destination for exactly one earning. This is the only endpoint that
    // returns the decrypted account number/IFSC; it is ADMIN-only and must not
    // be logged or cached. Pay first, then record the reference with the POST
    // below.
    router.get('/settlements/<paymentTransferId>/payout-destination', (
      Request req,
      String paymentTransferId,
    ) async {
      final adminId = await requireUserIdOfRole(
        req,
        allowedRoles: [UserRole.admin],
      );
      final payload = await _settlements.getPayoutDestination(
        transferId: paymentTransferId,
        adminUserId: adminId,
      );
      // This response contains a full account number + IFSC. Keep it out of
      // every shared/proxy/browser cache; it is meant for one admin action.
      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Payout destination loaded.',
          'data': payload,
        }),
        headers: const {
          'content-type': 'application/json',
          'cache-control': 'no-store, no-cache, must-revalidate',
          'pragma': 'no-cache',
        },
      );
    });

    // Mark one owner earning as settled after a real, out-of-band payout.
    // `{paymentTransferId}` is the `payment_transfers.id`.
    router.post('/settlements/<paymentTransferId>/mark-settled', (
      Request req,
      String paymentTransferId,
    ) async {
      final adminId = await requireUserIdOfRole(
        req,
        allowedRoles: [UserRole.admin],
      );
      final body = await readJsonBody(req) ?? {};
      final payload = await _settlements.markSettled(
        transferId: paymentTransferId,
        adminUserId: adminId,
        reference:
            body['manualPayoutReference']?.toString() ??
            body['reference']?.toString() ??
            '',
        note: body['note']?.toString() ?? '',
      );
      final already = payload['alreadySettled'] == true;
      return ApiResponse.ok(
        payload,
        already
            ? 'Settlement was already recorded; no change made.'
            : 'Settlement marked as settled.',
      );
    });

    return router.call;
  }
}
