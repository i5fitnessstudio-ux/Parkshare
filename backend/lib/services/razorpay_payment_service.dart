import 'dart:convert';

import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/booking.dart';
import 'package:parkshare_backend/services/booking_service.dart';
import 'package:parkshare_backend/services/razorpay_service.dart';
import 'package:postgres/postgres.dart';

/// Payment provider key stored on `payments.provider` / `payments.payment_method`
/// for Razorpay orders.
const String kRazorpayProvider = 'RAZORPAY';

/// Marketplace settlement states for a single payment.
class TransferStatus {
  TransferStatus._();
  static const String pending = 'PENDING';
  static const String transferred = 'TRANSFERRED';
  static const String failed = 'FAILED';
}

class SettlementStatus {
  SettlementStatus._();
  static const String pending = 'PENDING';
  static const String settled = 'SETTLED';
}

/// Orquestra o fluxo Razorpay do ParkShare.
///
/// This is a security-critical boundary: it is the ONLY place that may turn a
/// booking into PAID/CONFIRMED for an online payment, and it does so only after
/// a gateway HMAC has been verified (checkout signature or webhook signature).
/// It never trusts an amount or an owner/linked-account id supplied by Flutter.
class RazorpayPaymentService {
  RazorpayPaymentService({RazorpayService? razorpay})
    : _razorpay = razorpay ?? RazorpayService();

  final RazorpayService _razorpay;
  final BookingService _bookings = BookingService();

  // ---------------------------------------------------------------------
  // POST /api/payments/razorpay/order
  // ---------------------------------------------------------------------

  /// Creates a server-authoritative Razorpay order for [bookingId].
  ///
  /// The amount comes from `bookings.amount` (rupees) rounded to integer paise;
  /// any amount sent by the client is ignored. Returns only public data.
  Future<Map<String, dynamic>> createOrder({
    required String bookingId,
    required String userId,
  }) async {
    if (!_razorpay.isConfigured) {
      throw ApiError(
        503,
        'Online payment is not available right now. Please use Cash on '
        'Delivery or try again later.',
      );
    }

    // Persist the mode that created this order. A test-mode payment must stay
    // audit-only: settlement refuses it even after the backend is switched to
    // live keys. Production startup validates this value; this runtime check
    // also covers a development process started without that validation.
    final gatewayMode = Config.razorpayMode;
    if (gatewayMode != 'test' && gatewayMode != 'live') {
      throw ApiError(
        503,
        'Online payment is not available right now. Please use Cash on '
        'Delivery or try again later.',
      );
    }

    // Authorization: getById throws 404/403 unless this user may see it, and
    // also confirms the booking exists.
    final booking = await _bookings.getById(bookingId, viewerId: userId);

    final status = booking['status'].toString();
    if (status == BookingStatus.requested ||
        status == BookingStatus.rejected ||
        status == BookingStatus.cancelled) {
      throw ApiError.validation(
        'Payment requires owner approval first (booking is $status).',
      );
    }
    if (status == BookingStatus.codPending) {
      throw ApiError.conflict(
        'This booking is set up for Cash on Delivery. Contact the owner or '
        'start a new booking to pay online.',
      );
    }

    // Refuse to create a second order for an already-paid booking.
    final currentPayment = booking['paymentStatus'].toString();
    if (PaymentStatus.paid.contains(currentPayment)) {
      throw ApiError.conflict('This booking has already been paid.');
    }

    final amountRupees = (booking['amount'] as num?)?.toDouble();
    if (amountRupees == null || amountRupees <= 0) {
      throw ApiError.server('Booking amount is missing.');
    }
    final amountPaise = _rupeesToPaise(amountRupees);

    final ownerName = booking['ownerName']?.toString() ?? '';
    final parkingName =
        (booking['parking'] is Map
            ? (booking['parking'] as Map)['name']?.toString()
            : null) ??
        '';
    final bookingIdCompact = bookingId.replaceAll('-', '');
    final receipt = 'ps_$bookingIdCompact';

    final order = await _razorpay.createOrder(
      amountPaise: amountPaise,
      receipt: receipt.length > 40 ? receipt.substring(0, 40) : receipt,
      notes: {'bookingId': bookingId, 'userId': userId},
    );

    final String paymentId;
    try {
      paymentId = await Db.pool.withConnection((conn) async {
        return conn.runTx((tx) async {
          // One live attempt per booking: any earlier CREATED / PENDING
          // Razorpay row is retired so the ledger stays unambiguous.
          await tx.execute(
            Sql.named('''
            UPDATE payments
            SET payment_status = 'FAILED', updated_at = NOW()
            WHERE booking_id = @bookingId
              AND payment_method = @method
              AND payment_status IN ('CREATED', 'PENDING')
            '''),
            parameters: {'bookingId': bookingId, 'method': kRazorpayProvider},
          );

          final res = await tx.execute(
            Sql.named('''
            INSERT INTO payments (
              booking_id, user_id, owner_id, amount, amount_paise, currency,
              payment_method, provider, payment_status,
              razorpay_order_id, verification_status, razorpay_mode,
              reference, updated_at
            ) VALUES (
              @bookingId, @userId, @ownerId, @amount, @amountPaise, 'INR',
              @method, 'razorpay', 'CREATED',
              @orderId, 'UNVERIFIED', @razorpayMode, @reference, NOW()
            )
            RETURNING id
            '''),
            parameters: {
              'bookingId': bookingId,
              'userId': userId,
              'ownerId': booking['ownerId'].toString(),
              'amount': amountRupees,
              'amountPaise': amountPaise,
              'method': kRazorpayProvider,
              'orderId': order.id,
              'razorpayMode': gatewayMode,
              'reference': receipt,
            },
          );
          final id = res.first.toColumnMap()['id'].toString();

          await tx.execute(
            Sql.named('''
            UPDATE bookings
            SET payment_method = @method, payment_status = 'PENDING',
                payment_reference = @reference, updated_at = NOW()
            WHERE id = @id
            '''),
            parameters: {
              'id': bookingId,
              'method': kRazorpayProvider,
              'reference': receipt,
            },
          );
          return id;
        });
      });
    } on ServerException catch (e) {
      // A duplicate order/payment id (23505) means another request won the
      // race; the caller can simply reload.
      if (e.code == '23505') {
        throw ApiError.conflict(
          'A payment is already in progress for this booking. Please refresh.',
        );
      }
      rethrow;
    }

    return {
      'paymentId': paymentId,
      'bookingId': bookingId,
      // ONLY the public key id is returned — never the key secret.
      'razorpayOrderId': order.id,
      'razorpayKeyId': Config.razorpayKeyId,
      // Integer paise, as Checkout expects.
      'amount': amountPaise,
      'currency': order.currency.isEmpty ? 'INR' : order.currency,
      'ownerName': ownerName,
      'parkingName': parkingName,
    };
  }

  // ---------------------------------------------------------------------
  // POST /api/payments/razorpay/verify
  // ---------------------------------------------------------------------

  /// Verifies a Checkout callback signature and, when valid, marks the booking
  /// paid. Idempotent: repeating the same valid callback is a no-op.
  Future<Map<String, dynamic>> verifyCheckout({
    required String bookingId,
    required String userId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    if (razorpayOrderId.isEmpty ||
        razorpayPaymentId.isEmpty ||
        razorpaySignature.isEmpty) {
      throw ApiError.validation(
        'razorpayOrderId, razorpayPaymentId and razorpaySignature are required.',
      );
    }

    // Authorization + existence.
    await _bookings.getById(bookingId, viewerId: userId);

    final payment = await _paymentByOrder(bookingId, razorpayOrderId);
    if (payment == null) {
      throw ApiError.validation('Unknown payment order for this booking.');
    }

    final ok = RazorpayService.verifyCheckoutSignature(
      orderId: razorpayOrderId,
      paymentId: razorpayPaymentId,
      signature: razorpaySignature,
      secret: Config.razorpayKeySecret,
    );
    if (!ok) {
      throw ApiError.validation('Invalid payment signature.');
    }

    // Idempotency: a repeated, valid callback for an already-paid payment must
    // not hit the gateway again, and must never attach a DIFFERENT payment id
    // to the same order/payment row.
    if (payment['payment_status']?.toString() == PaymentStatus.success) {
      final storedPaymentId = payment['razorpay_payment_id']?.toString() ?? '';
      if (storedPaymentId.isNotEmpty && storedPaymentId != razorpayPaymentId) {
        throw ApiError.conflict(
          'This order was already settled by a different Razorpay payment.',
        );
      }
      // Heal a payment left SUCCESS without its booking/ledger writes by an
      // older non-atomic workflow. _markPaid is idempotent; if the booking is
      // genuinely no longer payable it throws instead of pretending it paid.
      await _markPaid(
        payment: payment,
        razorpayPaymentId: storedPaymentId.isEmpty
            ? razorpayPaymentId
            : storedPaymentId,
        source: 'checkout',
      );
      return _bookings.getById(bookingId, viewerId: userId);
    }

    // SECURITY: the HMAC proves the Checkout callback was not forged, but it
    // does NOT prove the payment was actually captured. Independently fetch the
    // payment from Razorpay and require:
    //   * it belongs to THIS order,
    //   * it is `captured` (not merely `authorized`),
    //   * its amount/currency match the server-stored order exactly.
    // A forged/tampered amount or a reused order can therefore never confirm a
    // booking, even if the client somehow obtains a valid signature for one.
    final Map<String, dynamic> entity;
    try {
      entity = await _razorpay.fetchPayment(razorpayPaymentId);
    } on RazorpayException catch (e) {
      if (e.statusCode == 400 || e.statusCode == 404) {
        throw ApiError.validation(
          'The payment could not be found at the payment gateway.',
        );
      }
      // Transient/transport failure: report it as unavailable so the client
      // keeps the attempt in "pending verification" and never calls it paid.
      throw ApiError(503, e.userMessage);
    }

    final problem = capturedPaymentProblem(
      payment: entity,
      expectedOrderId: razorpayOrderId,
      expectedAmountPaise: _storedPaise(payment),
    );
    if (problem != null) {
      if (problem.startsWith('not-captured:')) {
        final gatewayStatus = problem.substring('not-captured:'.length);
        if (gatewayStatus == 'failed') {
          // The signature was valid, so this is a known failure for this
          // order. Mirror it onto the booking before telling the client, so
          // the UI does not remain stuck on PENDING.
          await _markOrderFailed(razorpayOrderId);
          throw ApiError.validation(
            'Razorpay did not capture this payment. Please try again.',
          );
        }
        // `created` / `authorized` are not settled yet. Return the booking
        // unchanged so the client shows "pending verification"; a later
        // captured webhook (or a retry of this endpoint) can still complete it.
        return _bookings.getById(bookingId, viewerId: userId);
      }
      throw ApiError.validation(
        'The Razorpay payment does not match this booking ($problem).',
      );
    }

    await _markPaid(
      payment: payment,
      razorpayPaymentId: razorpayPaymentId,
      source: 'checkout',
    );

    return _bookings.getById(bookingId, viewerId: userId);
  }

  /// Returns `null` when [payment] is the captured gateway payment for
  /// [expectedOrderId] at [expectedAmountPaise]; otherwise a stable reason.
  ///
  /// Pure and public so the money-critical checks can be unit-tested without a
  /// database or network. The "not-captured:" prefix tells the caller the
  /// payment is merely not settled yet (retry later) rather than fraudulent.
  static String? capturedPaymentProblem({
    required Map<String, dynamic> payment,
    required String expectedOrderId,
    required int expectedAmountPaise,
  }) {
    final orderId = payment['order_id']?.toString() ?? '';
    if (orderId.isEmpty || orderId != expectedOrderId) {
      return 'order-mismatch';
    }

    final status = payment['status']?.toString().toLowerCase() ?? '';
    if (status != 'captured') {
      return 'not-captured:$status';
    }

    final rawAmount = payment['amount'];
    final amountPaise = rawAmount is num
        ? rawAmount.toInt()
        : int.tryParse('$rawAmount');
    if (expectedAmountPaise <= 0) return 'stored-amount-missing';
    if (amountPaise == null || amountPaise != expectedAmountPaise) {
      return 'amount-mismatch';
    }

    final currency = payment['currency']?.toString().toUpperCase() ?? '';
    if (currency.isNotEmpty && currency != 'INR') {
      return 'currency-mismatch';
    }
    return null;
  }

  /// True only for an event that proves the money was CAPTURED.
  ///
  /// `payment.authorized` is deliberately excluded: authorization is not
  /// settlement. Pure so the event classification is regression-tested.
  static bool isCapturedEvent(String event, String? entityStatus) {
    if (event != 'payment.captured' && event != 'order.paid') return false;
    return (entityStatus ?? '').toLowerCase() == 'captured';
  }

  // ---------------------------------------------------------------------
  // POST /api/webhooks/razorpay
  // ---------------------------------------------------------------------

  /// Verifies and processes a Razorpay webhook.
  ///
  /// [rawBody] MUST be the exact bytes Razorpay signed (never a re-encoded
  /// JSON). Returns a small status map so the webhook caller can answer 200.
  Future<Map<String, dynamic>> processWebhook({
    required String rawBody,
    required String signature,
    String eventIdFromHeader = '',
  }) async {
    if (!Config.razorpayWebhookConfigured) {
      throw ApiError(503, 'Webhook is not configured on this server.');
    }
    if (!RazorpayService.verifyWebhookSignature(
      rawBody: rawBody,
      signature: signature,
      secret: Config.razorpayWebhookSecret,
    )) {
      throw ApiError.validation('Invalid webhook signature.');
    }

    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('not an object');
      }
      body = decoded;
    } catch (_) {
      throw ApiError.validation('Malformed webhook payload.');
    }

    final event = body['event']?.toString() ?? '';
    final entity = _paymentEntity(body);
    final razorpayOrderId = entity?['order_id']?.toString() ?? '';
    final razorpayPaymentId = entity?['id']?.toString() ?? '';
    final entityStatus = entity?['status']?.toString() ?? '';
    final eventKey = eventIdFromHeader.isNotEmpty
        ? eventIdFromHeader
        : _deterministicEventKey(event, razorpayPaymentId, entityStatus);

    // Idempotency: a fully processed event_key is a no-op, but an event that
    // was inserted by an earlier attempt and then FAILED to process must be
    // allowed to retry. `ON CONFLICT DO NOTHING` made that impossible: the row
    // existed with `processed_at IS NULL`, so every Razorpay retry looked like a
    // duplicate and the payment was never applied.
    final claimed = await Db.pool.withConnection((conn) async {
      final res = await conn.execute(
        Sql.named('''
        INSERT INTO razorpay_webhook_events (
          event_key, event_type, razorpay_order_id, razorpay_payment_id, payload
        ) VALUES (
          @key, @type, NULLIF(@orderId, ''), NULLIF(@paymentId, ''), @payload
        )
        ON CONFLICT (event_key) DO UPDATE
        SET event_type = EXCLUDED.event_type,
            razorpay_order_id = EXCLUDED.razorpay_order_id,
            razorpay_payment_id = EXCLUDED.razorpay_payment_id,
            payload = EXCLUDED.payload
        WHERE razorpay_webhook_events.processed_at IS NULL
        RETURNING id
        '''),
        parameters: {
          'key': eventKey,
          'type': event,
          'orderId': razorpayOrderId,
          'paymentId': razorpayPaymentId,
          'payload': jsonEncode(_sanitiseEvent(body)),
        },
      );
      return res.isNotEmpty;
    });

    if (!claimed) {
      return {'duplicate': true, 'event': event};
    }

    var handled = 'ignored';
    switch (event) {
      case 'payment.captured':
      case 'order.paid':
        handled = await _handleSuccessfulPayment(
          razorpayOrderId: razorpayOrderId,
          razorpayPaymentId: razorpayPaymentId,
          entity: entity,
        );
        break;
      case 'payment.authorized':
        // An authorization only reserves funds; it does NOT settle them.
        // Treating it as paid was a critical bug: a customer could authorize a
        // payment, never capture it, and still get a confirmed booking. Only
        // `payment.captured` / `order.paid` with a captured entity may settle.
        handled = 'ignored:not-captured';
        break;
      case 'payment.failed':
        handled = await _handleFailedPayment(razorpayOrderId: razorpayOrderId);
        break;
      default:
        break;
    }

    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('''
        UPDATE razorpay_webhook_events
        SET processed_at = NOW()
        WHERE event_key = @key
        '''),
        parameters: {'key': eventKey},
      );
    });

    return {'duplicate': false, 'event': event, 'handled': handled};
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  /// Marks a payment authoritatively paid and cascades exactly once.
  ///
  /// Re-runnable: if the payment is already SUCCESS it still ensures the
  /// booking is confirmed and the owner earning exists, so a webhook arriving
  /// after the checkout callback (or vice-versa) cannot double anything.
  Future<void> _markPaid({
    required Map<String, dynamic> payment,
    required String razorpayPaymentId,
    required String source,
  }) async {
    final paymentId = payment['id'].toString();
    final verification = source == 'webhook'
        ? 'WEBHOOK_VERIFIED'
        : 'SIGNATURE_VERIFIED';
    late String bookingId;
    late String ownerId;
    late int grossPaise;

    await Db.pool.withConnection((conn) async {
      await conn.runTx((tx) async {
        // Lock the payment first. All three writes below are in this one
        // transaction: payment + booking + owner ledger. If the booking can no
        // longer be confirmed (for example it was cancelled while Checkout was
        // open), the transaction rolls back instead of recording money against
        // a booking that does not exist in a payable state.
        final res = await tx.execute(
          Sql.named('''
          SELECT booking_id, owner_id, payment_status, razorpay_payment_id,
                 amount_paise, amount
          FROM payments
          WHERE id = @id
          FOR UPDATE
          '''),
          parameters: {'id': paymentId},
        );
        if (res.isEmpty) {
          throw ApiError.conflict(
            'The local payment record no longer exists. No payment was '
            'recorded; the gateway payment needs manual review or refund.',
          );
        }
        final row = res.first.toColumnMap();
        bookingId = row['booking_id']?.toString() ?? '';
        ownerId = row['owner_id']?.toString() ?? '';
        if (bookingId.isEmpty || ownerId.isEmpty) {
          throw ApiError.conflict(
            'The local payment record is incomplete. No payment was recorded; '
            'the gateway payment needs manual review or refund.',
          );
        }

        final storedPaymentId = row['razorpay_payment_id']?.toString() ?? '';
        if (storedPaymentId.isNotEmpty &&
            storedPaymentId != razorpayPaymentId) {
          throw ApiError.conflict(
            'This order was already settled by a different Razorpay payment.',
          );
        }

        grossPaise = _intOr(row['amount_paise'], 0);
        if (grossPaise <= 0) {
          grossPaise = _amountColumnToPaise(row['amount']);
        }

        // Re-running is safe. A repeat may fill a missing gateway payment id
        // on an older row, but never replaces a different one.
        await tx.execute(
          Sql.named('''
          UPDATE payments
          SET payment_status = 'SUCCESS',
              razorpay_payment_id = @paymentId,
              razorpay_status = 'captured',
              verification_status = @verification,
              transaction_id = COALESCE(transaction_id, @paymentId),
              paid_at = COALESCE(paid_at, NOW()),
              verified_at = COALESCE(verified_at, NOW()),
              updated_at = NOW()
          WHERE id = @id
          '''),
          parameters: {
            'id': paymentId,
            'paymentId': razorpayPaymentId,
            'verification': verification,
          },
        );

        // Throws and rolls back everything above when the booking is no longer
        // payable. It is idempotent for an already-confirmed booking.
        await _bookings.confirmOnlinePaymentInTransaction(
          tx,
          bookingId: bookingId,
        );

        await _recordOwnerEarningInTransaction(
          tx,
          paymentId: paymentId,
          bookingId: bookingId,
          ownerId: ownerId,
          amountPaise: grossPaise,
        );
      });
    });

    // Route is opt-in and happens after the money state is committed. When it
    // is disabled NOTHING is transferred and the earning stays PENDING until
    // manual settlement. A failed Route call also leaves the row PENDING.
    if (Config.razorpayRouteEnabled) {
      await _attemptRouteTransfer(
        paymentId: paymentId,
        ownerId: ownerId,
        razorpayPaymentId: razorpayPaymentId,
      );
    }
  }

  /// Persists the owner-earning / transfer row inside the caller's transaction.
  ///
  /// UNIQUE(payment_id) plus DO NOTHING makes a webhook/Checkout replay safe.
  Future<void> _recordOwnerEarningInTransaction(
    dynamic tx, {
    required String paymentId,
    required String bookingId,
    required String ownerId,
    required int amountPaise,
  }) async {
    final gross = amountPaise < 0 ? 0 : amountPaise;
    final fee = (gross * Config.parkShareCommissionPercent / 100).round();
    final ownerAmount = gross - fee;

    await tx.execute(
      Sql.named('''
      INSERT INTO payment_transfers (
        payment_id, booking_id, owner_id,
        gross_amount_paise, platform_fee_paise, owner_amount_paise,
        currency, transfer_status, settlement_status
      ) VALUES (
        @paymentId, @bookingId, @ownerId,
        @gross, @fee, @ownerAmount,
        'INR', 'PENDING', @settlement
      )
      ON CONFLICT (payment_id) DO NOTHING
      '''),
      parameters: {
        'paymentId': paymentId,
        'bookingId': bookingId,
        'ownerId': ownerId,
        'gross': gross,
        'fee': fee,
        'ownerAmount': ownerAmount,
        'settlement': SettlementStatus.pending,
      },
    );
  }

  static int _amountColumnToPaise(Object? value) {
    final rupees = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    if (rupees <= 0) return 0;
    return (rupees * 100).round();
  }

  /// Best-effort Route transfer of the owner share to the booking owner's
  /// linked account. Never accepts a linked account from a client.
  Future<void> _attemptRouteTransfer({
    required String paymentId,
    required String ownerId,
    required String razorpayPaymentId,
  }) async {
    if (razorpayPaymentId.isEmpty) return;

    final account = await Db.pool.withConnection((conn) async {
      final res = await conn.execute(
        Sql.named('''
        SELECT razorpay_linked_account_id, razorpay_settlement_enabled
        FROM owner_payment_accounts
        WHERE owner_id = @ownerId
        '''),
        parameters: {'ownerId': ownerId},
      );
      if (res.isEmpty) return null;
      return res.first.toColumnMap();
    });

    final linkedAccountId =
        account?['razorpay_linked_account_id']?.toString() ?? '';
    if (account == null ||
        account['razorpay_settlement_enabled'] != true ||
        linkedAccountId.isEmpty) {
      // No linked account yet: leave the earning PENDING. Do not fake a
      // transfer.
      return;
    }

    final transferRow = await Db.pool.withConnection((conn) async {
      final res = await conn.execute(
        Sql.named('''
        SELECT id, owner_amount_paise, razorpay_transfer_id, transfer_status
        FROM payment_transfers
        WHERE payment_id = @paymentId
        '''),
        parameters: {'paymentId': paymentId},
      );
      if (res.isEmpty) return null;
      return res.first.toColumnMap();
    });
    if (transferRow == null) return;
    // Already transferred: reconcile instead of creating a second transfer.
    if ((transferRow['razorpay_transfer_id']?.toString() ?? '').isNotEmpty) {
      return;
    }

    try {
      final result = await _razorpay.createTransfer(
        razorpayPaymentId: razorpayPaymentId,
        amountPaise: _intOr(transferRow['owner_amount_paise'], 0),
        linkedAccountId: linkedAccountId,
        notes: {'paymentId': paymentId},
      );
      final transferId = _firstTransferId(result);
      await Db.pool.withConnection((conn) async {
        await conn.execute(
          Sql.named('''
          UPDATE payment_transfers
          SET razorpay_transfer_id = @transferId,
              razorpay_linked_account_id = @account,
              transfer_status = 'TRANSFERRED',
              updated_at = NOW()
          WHERE payment_id = @paymentId
            AND razorpay_transfer_id IS NULL
          '''),
          parameters: {
            'paymentId': paymentId,
            'transferId': transferId,
            'account': linkedAccountId,
          },
        );
      });
    } on RazorpayException catch (e) {
      await Db.pool.withConnection((conn) async {
        await conn.execute(
          Sql.named('''
          UPDATE payment_transfers
          SET transfer_status = 'FAILED', failure_reason = @reason,
              updated_at = NOW()
          WHERE payment_id = @paymentId
            AND razorpay_transfer_id IS NULL
          '''),
          parameters: {
            'paymentId': paymentId,
            'reason': '${e.code ?? 'ERROR'} (${e.statusCode})',
          },
        );
      });
    }
  }

  Future<String> _handleSuccessfulPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required Map<String, dynamic>? entity,
  }) async {
    if (razorpayOrderId.isEmpty) return 'ignored:no-order';
    if (razorpayPaymentId.isEmpty) return 'ignored:no-payment';

    // Only a captured entity proves settlement. An `authorized` payment can
    // still fail or expire, so it must never confirm a booking.
    if (!isCapturedEvent('payment.captured', entity?['status']?.toString())) {
      return 'ignored:not-captured';
    }

    final payment = await _paymentByOrderIdOnly(razorpayOrderId);
    if (payment == null) return 'ignored:unknown-order';

    // The payment id must belong to this order (the gateway entity carries
    // both, and we only look up by that order id).
    final eventOrderId = entity?['order_id']?.toString() ?? '';
    if (eventOrderId.isNotEmpty && eventOrderId != razorpayOrderId) {
      return 'ignored:order-mismatch';
    }

    // Strict amount check: Razorpay signs the amount, but a server-side amount
    // that is missing or different must never be marked paid.
    final storedPaise = _storedPaise(payment);
    final eventPaise = _intOr(entity?['amount'], 0);
    if (storedPaise <= 0 || eventPaise != storedPaise) {
      return 'ignored:amount-mismatch';
    }
    final currency = entity?['currency']?.toString().toUpperCase() ?? '';
    if (currency.isNotEmpty && currency != 'INR') {
      return 'ignored:currency-mismatch';
    }

    await _markPaid(
      payment: payment,
      razorpayPaymentId: razorpayPaymentId,
      source: 'webhook',
    );
    return 'paid';
  }

  Future<String> _handleFailedPayment({required String razorpayOrderId}) async {
    if (razorpayOrderId.isEmpty) return 'ignored:no-order';
    await _markOrderFailed(razorpayOrderId);
    return 'failed';
  }

  /// Mirrors a gateway failure onto both the payment and the booking row.
  ///
  /// The original code updated only `payments`. The Flutter payment screen
  /// reads `bookings.paymentStatus`, so a failed online attempt kept showing
  /// `PENDING` and could not be distinguished from an attempt in progress.
  ///
  /// Both writes are in one transaction, and neither can overwrite a SUCCESS
  /// row. A late `payment.failed` event therefore cannot erase a captured
  /// payment.
  Future<void> _markOrderFailed(String razorpayOrderId) async {
    await Db.pool.withConnection((conn) async {
      await conn.runTx((tx) async {
        await tx.execute(
          Sql.named('''
          UPDATE payments
          SET payment_status = 'FAILED', razorpay_status = 'failed',
              verification_status = 'GATEWAY_FAILED', updated_at = NOW()
          WHERE razorpay_order_id = @orderId
            AND payment_status <> 'SUCCESS'
          '''),
          parameters: {'orderId': razorpayOrderId},
        );
        await tx.execute(
          Sql.named('''
          UPDATE bookings b
          SET payment_status = 'FAILED', updated_at = NOW()
          WHERE b.id IN (
            SELECT p.booking_id
            FROM payments p
            WHERE p.razorpay_order_id = @orderId
              AND p.payment_status = 'FAILED'
          )
            AND b.payment_method = 'RAZORPAY'
            AND b.payment_status <> 'SUCCESS'
            AND b.status IN ('ACCEPTED', 'PAYMENT_PENDING')
          '''),
          parameters: {'orderId': razorpayOrderId},
        );
      });
    });
  }

  Future<Map<String, dynamic>?> _paymentByOrder(
    String bookingId,
    String orderId,
  ) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT * FROM payments
        WHERE booking_id = @bookingId
          AND razorpay_order_id = @orderId
          AND payment_method = @method
        ORDER BY created_at DESC
        LIMIT 1
        '''),
        parameters: {
          'bookingId': bookingId,
          'orderId': orderId,
          'method': kRazorpayProvider,
        },
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  Future<Map<String, dynamic>?> _paymentByOrderIdOnly(String orderId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT * FROM payments
        WHERE razorpay_order_id = @orderId
        ORDER BY created_at DESC
        LIMIT 1
        '''),
        parameters: {'orderId': orderId},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  /// Integer paise for a payment row (never derived unsafely elsewhere).
  static int _storedPaise(Map<String, dynamic> payment) {
    final paise = payment['amount_paise'];
    if (paise is num) return paise.toInt();
    final parsed = int.tryParse('$paise');
    if (parsed != null && parsed > 0) return parsed;
    final rupees = (payment['amount'] as num?)?.toDouble() ?? 0;
    if (rupees <= 0) return 0;
    return rupeesToPaise(rupees);
  }

  /// Razorpay payment entity from a webhook body.
  static Map<String, dynamic>? _paymentEntity(Map<String, dynamic> body) {
    final payload = body['payload'];
    if (payload is! Map) return null;
    final payment = payload['payment'];
    if (payment is! Map) return null;
    final entity = payment['entity'];
    if (entity is! Map) return null;
    return entity.cast<String, dynamic>();
  }

  /// Strips anything that could be sensitive before the payload is persisted.
  static Map<String, dynamic> _sanitiseEvent(Map<String, dynamic> body) {
    // Razorpay payloads do not carry our secrets, but we keep only the event
    // and the payment entity so the stored blob stays small and predictable.
    return {'event': body['event'], 'payment': _paymentEntity(body)};
  }

  static String _deterministicEventKey(
    String event,
    String paymentId,
    String status,
  ) {
    final stable = paymentId.isNotEmpty ? paymentId : 'unknown';
    return '$event:$stable:$status';
  }

  static String _firstTransferId(Map<String, dynamic> result) {
    final transfers = result['transfers'];
    if (transfers is List && transfers.isNotEmpty) {
      final first = transfers.first;
      if (first is Map && first['id'] != null) return first['id'].toString();
    }
    return result['id']?.toString() ?? '';
  }

  /// ₹ → integer paise without floating-point drift.
  static int _rupeesToPaise(double rupees) => rupeesToPaise(rupees);

  static int _intOr(Object? value, int fallback) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
}

/// ₹ → integer paise, rounded to the nearest paise.
///
/// Public so it can be unit-tested directly: authoritative money in this
/// service is always integer paise, never a double.
int rupeesToPaise(double rupees) => (rupees * 100).round();

/// Public helper used by internals above (kept outside the class to stay
/// readable next to the row they read).
int rowPaise(Map<String, dynamic> payment) => payment['amount_paise'] is num
    ? (payment['amount_paise'] as num).toInt()
    : 0;
