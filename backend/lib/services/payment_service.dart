import 'dart:convert';
import 'dart:math';

import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/booking.dart';
import 'package:parkshare_backend/services/booking_service.dart';
import 'package:parkshare_backend/services/parking_service.dart';
import 'package:postgres/postgres.dart';

/// Message shown to the client so it can explain the honest state of a UPI
/// payment the backend could not verify. Kept in one place because the API
/// response and the settlement flow must never disagree about it.
const String kUpiUnverifiedMessage =
    'We have recorded your UPI payment, but it cannot be verified by the app '
    'yet. The parking owner will check it against their account and confirm '
    'it, and your booking is confirmed once they do.';

/// Payment domain service — the two supported methods only:
///
///  * **UPI** — the money goes to the *selected parking owner's own* UPI id
///    (`users.upi_id`, snapshotted on the booking at creation time). The app
///    opens a `upi://pay` intent with that address, then calls [confirmUpi]
///    when the user comes back and declares the UPI app showed success.
///
///    SECURITY (audit C-01): a `upi://` intent is a one-way, unsigned hand-off.
///    The UPI app tells the *user's phone* what happened; it never signs
///    anything and never talks to this backend. So [confirmUpi] CANNOT verify
///    settlement, and this service therefore refuses to pretend it did:
///
///      * a `PENDING` row created by [createUpiIntent] MUST exist — no row is
///        ever created implicitly, so a client cannot skip straight to a paid
///        booking;
///      * the outcome is recorded as [PaymentStatus.upiPendingVerification]
///        ("claimed, not verified"), NOT `SUCCESS`;
///      * the booking is NOT flipped to CONFIRMED, holds no slot and earns the
///        owner nothing;
///      * no transaction id is ever invented — the server stores only what the
///        client actually reported, which may legitimately be nothing.
///
///    The only path from that state to `SUCCESS` is [settleUpi], driven by the
///    parking owner (or, in future, by a PSP webhook). Until one of those
///    exists, this API cannot and does not confirm UPI money.
///  * **COD** — no money moves on the server. The booking is created as
///    COD_PENDING and keeps the slot AVAILABLE, because the user has not paid
///    yet. Only when the owner calls [confirmCod] does the slot get allocated,
///    the booking become CONFIRMED and the amount enter Total Earnings.
///
/// Card and NetBanking were removed: a payment must always be traceable to one
/// owner's UPI id, or to a cash handover the owner confirms.
class PaymentService {
  final BookingService _bookingService = BookingService();

  /// AUDIT M-07: identifiers must not be predictable, so this is the CSPRNG
  /// (matching AuthService) rather than `Random()`.
  static final Random _random = Random.secure();
  static const _bookingIdLength = 8;

  // ---------------------------------------------------------------------
  // Owner payment info for a selected parking
  // ---------------------------------------------------------------------
  /// Everything the payment screen needs about the owner of [parkingId]:
  /// their name, phone, and their OWN UPI id (never a global one).
  ///
  /// `hasUpiId` drives the UI: when it is false the UPI option must show the
  /// "owner has not configured a UPI ID yet" message and the user is pushed
  /// to Cash on Delivery.
  Future<Map<String, dynamic>> ownerPaymentInfo(String parkingId) async {
    if (parkingId.isEmpty || !ParkingService.isUuid(parkingId)) {
      throw ApiError.validation('A valid parkingId is required.');
    }
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT p.id, p.parking_name, p.address, p.city,
               u.id AS owner_id, u.name AS owner_name, u.phone AS owner_phone,
               u.upi_id AS owner_upi_id
        FROM parking_listings p
        JOIN users u ON u.id = p.owner_id
        WHERE p.id = @id
        '''),
        parameters: {'id': parkingId},
      );
    });
    if (res.isEmpty) throw ApiError.notFound('Parking listing not found.');
    final row = res.first.toColumnMap();
    final upiId = _cleanUpi(row['owner_upi_id']);
    return {
      'parkingId': row['id'].toString(),
      'parkingName': row['parking_name']?.toString() ?? '',
      'address': row['address']?.toString() ?? '',
      'city': row['city']?.toString(),
      'ownerId': row['owner_id'].toString(),
      'ownerName': row['owner_name']?.toString() ?? '',
      'ownerPhone': _cleanPhone(row['owner_phone']),
      'ownerUpiId': upiId,
      'hasUpiId': upiId != null,
      // The only two methods the app offers.
      'paymentMethods': PaymentMethod.all.toList(),
      'upiAvailable': upiId != null,
      'codAvailable': true,
    };
  }

  // ---------------------------------------------------------------------
  // UPI
  // ---------------------------------------------------------------------

  /// Creates (or refreshes) the PENDING payment for a booking and returns the
  /// exact payload the app must hand to the UPI app.
  ///
  /// Throws a 400 with a clear message when the selected parking's owner has
  /// no UPI id — the caller turns that into
  /// "This parking owner has not configured a UPI ID yet…".
  Future<Map<String, dynamic>> createUpiIntent({
    required String bookingId,
    required String userId,
  }) async {
    final booking = await _payableBooking(bookingId, viewerId: userId);
    final ownerId = booking['ownerId'].toString();
    final ownerUpi = _cleanUpi(booking['ownerUpiId']);
    if (ownerUpi == null) {
      throw ApiError.validation(
        'This parking owner has not configured a UPI ID yet. Please choose '
        'Cash on Delivery or contact the owner.',
      );
    }

    final amount = (booking['amount'] as num).toDouble();
    final reference = _reference();
    final ownerName = (booking['ownerName']?.toString() ?? '').trim();
    final parkingName =
        (booking['parking'] is Map
                ? (booking['parking'] as Map)['name']?.toString()
                : null)
            ?.trim() ??
        '';

    await Db.pool.withConnection((conn) async {
      // One live PENDING row per booking: drop any earlier attempt so the
      // dashboard never shows two half-finished payments.
      await conn.execute(
        Sql.named('''
        UPDATE payments
        SET payment_status = 'FAILED', updated_at = NOW()
        WHERE booking_id = @bookingId
          AND payment_method = 'UPI'
          AND payment_status = 'PENDING'
        '''),
        parameters: {'bookingId': bookingId},
      );
      await conn.execute(
        Sql.named('''
        INSERT INTO payments (
          booking_id, user_id, owner_id, amount, payment_method,
          payment_status, transaction_id, upi_id, reference
        ) VALUES (
          @bookingId, @userId, @ownerId, @amount, 'UPI',
          'PENDING', NULL, @upiId, @reference
        )
        '''),
        parameters: {
          'bookingId': bookingId,
          'userId': userId,
          'ownerId': ownerId,
          'amount': amount,
          'upiId': ownerUpi,
          'reference': reference,
        },
      );
      // Freeze the payee on the booking row so a later owner edit cannot
      // change where this booking was paid.
      await conn.execute(
        Sql.named('''
        UPDATE bookings
        SET payment_method = 'UPI', payment_status = 'PENDING',
            owner_upi_id_snapshot = @upiId, payment_reference = @reference,
            updated_at = NOW()
        WHERE id = @id
        '''),
        parameters: {
          'id': bookingId,
          'upiId': ownerUpi,
          'reference': reference,
        },
      );
    });

    return {
      'bookingId': bookingId,
      'paymentMethod': PaymentMethod.upi,
      'paymentStatus': PaymentStatus.pending,
      'amount': amount,
      'currency': 'INR',
      // Exact destination: the selected owner's own UPI id.
      'upiId': ownerUpi,
      'payeeName': ownerName.isEmpty ? 'Parking Owner' : ownerName,
      'ownerId': ownerId,
      'reference': reference,
      'note': _note(reference, parkingName),
    };
  }

  /// Called by the app after the user returns from the UPI app and declares
  /// that the payment went through.
  ///
  /// SECURITY (audit C-01, was CRITICAL). This endpoint used to accept the
  /// client's word as proof: it invented a `TXN…` transaction id when the
  /// client sent none, INSERTed a brand-new `SUCCESS` payment row when no
  /// attempt existed, and flipped the booking to CONFIRMED — which put the
  /// amount straight into the owner's Total Earnings. One authenticated HTTP
  /// call with an empty body bought a free, "paid", confirmed booking.
  ///
  /// It now enforces the only defensible behaviour:
  ///   1. a `PENDING` UPI attempt from [createUpiIntent] must already exist,
  ///      otherwise `409` — nothing is ever inserted implicitly;
  ///   2. the attempt moves to [PaymentStatus.upiPendingVerification], never
  ///      to `SUCCESS`, and `paid_at` stays NULL;
  ///   3. the booking status is NOT changed, so no slot is consumed;
  ///   4. `transaction_id` stores ONLY what the caller actually reported (it
  ///      may legitimately be NULL). The server never fabricates one;
  ///   5. the response carries an explicit `paymentVerification` block so the
  ///      client cannot mistake this for a settled payment.
  ///
  /// Repeating the call is safe: the second time there is no `PENDING` row any
  /// more, so it returns the already-submitted booking unchanged.
  Future<Map<String, dynamic>> confirmUpi({
    required String bookingId,
    required String userId,
    String? transactionId,
    String? reference,
    Map<String, dynamic>? rawResponse,
  }) async {
    final booking = await _payableBooking(bookingId, viewerId: userId);
    final current = booking['status'].toString();
    if (current == BookingStatus.confirmed || current == BookingStatus.active) {
      // Idempotent: a retried confirmation must not double-book.
      return booking;
    }

    final attempt = await _liveUpiAttempt(bookingId);
    if (attempt == null) {
      // Either the intent was never created, or it was already submitted (or
      // cancelled). Both are refused — a SUCCESS row is never manufactured.
      throw ApiError.conflict(
        'There is no pending UPI payment for this booking. Start the payment '
        'from the booking first; a payment cannot be confirmed without a '
        'pending transaction.',
      );
    }

    // Never invent a gateway reference. `COALESCE` on the client-supplied id
    // means "whatever was reported, possibly nothing at all".
    final reportedTxn = (transactionId?.trim().isNotEmpty ?? false)
        ? transactionId!.trim()
        : null;
    final storedRef = (reference?.trim().isNotEmpty ?? false)
        ? reference!.trim()
        : (attempt['reference']?.toString().trim() ?? '');
    final meta = jsonEncode({
      'source': 'client-declaration',
      'verification': 'unverified',
      'transactionId': reportedTxn,
      'declaredAt': DateTime.now().toUtc().toIso8601String(),
      'raw': ?rawResponse,
    });

    await Db.pool.withConnection((conn) async {
      await conn.runTx((tx) async {
        final updated = await tx.execute(
          Sql.named('''
          UPDATE payments
          SET payment_status = @unverified,
              transaction_id = COALESCE(@txn, transaction_id),
              raw_response = COALESCE(@raw, raw_response),
              updated_at = NOW()
          WHERE booking_id = @bookingId
            AND payment_method = 'UPI'
            AND payment_status = 'PENDING'
          '''),
          parameters: {
            'bookingId': bookingId,
            'unverified': PaymentStatus.upiPendingVerification,
            'txn': reportedTxn,
            'raw': meta,
          },
        );
        if (updated.affectedRows == 0) {
          // Lost a race with a concurrent confirm/fail: nothing to do, the
          // attempt is no longer PENDING.
          throw ApiError.conflict(
            'This UPI payment is no longer pending. Please refresh and try '
            'again.',
          );
        }
        // The booking keeps its status (ACCEPTED / PAYMENT_PENDING): an
        // unverified payment must not occupy the slot, exactly like a pending
        // cash payment.
        await tx.execute(
          Sql.named('''
          UPDATE bookings
          SET payment_method = 'UPI',
              payment_status = @unverified,
              payment_reference = COALESCE(payment_reference, NULLIF(@ref, '')),
              updated_at = NOW()
          WHERE id = @id
          '''),
          parameters: {
            'id': bookingId,
            'unverified': PaymentStatus.upiPendingVerification,
            'ref': storedRef,
          },
        );
      });
    });

    final updated = await _bookingService.getById(bookingId, viewerId: userId);
    return {...updated, 'paymentVerification': _verificationBlock()};
  }

  /// The block every client needs so it can never render this as "paid".
  static Map<String, dynamic> _verificationBlock() => {
    'verified': false,
    'status': PaymentStatus.upiPendingVerification,
    'requiresOwnerSettlement': true,
    'countsAsEarnings': false,
    'holdsSlot': false,
    'message': kUpiUnverifiedMessage,
  };

  /// The live `PENDING` UPI attempt for a booking, or null.
  ///
  /// Exposed to the tests: this is the single guard that makes a fabricated
  /// `SUCCESS` impossible.
  Future<Map<String, dynamic>?> _liveUpiAttempt(String bookingId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT id, reference, transaction_id, upi_id, amount
        FROM payments
        WHERE booking_id = @bookingId
          AND payment_method = 'UPI'
          AND payment_status = 'PENDING'
        ORDER BY created_at DESC
        LIMIT 1
        '''),
        parameters: {'bookingId': bookingId},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  /// Records a failed / cancelled UPI attempt. The booking keeps its status so
  /// the user can retry from the same screen.
  Future<Map<String, dynamic>> failUpi({
    required String bookingId,
    required String userId,
    String? reason,
  }) async {
    await _payableBooking(bookingId, viewerId: userId);
    await Db.pool.withConnection((conn) async {
      final cancelled = await conn.execute(
        Sql.named('''
        UPDATE payments
        SET payment_status = 'FAILED',
            raw_response = COALESCE(raw_response, @raw),
            updated_at = NOW()
        WHERE booking_id = @bookingId
          AND payment_method = 'UPI'
          AND payment_status = 'PENDING'
        '''),
        parameters: {
          'bookingId': bookingId,
          'raw': reason == null ? null : jsonEncode({'reason': reason}),
        },
      );
      // SECURITY (audit C-01 follow-up): the booking mirror must only follow an
      // attempt that really was pending. Without this guard a late "cancelled"
      // call could overwrite a payment that is already awaiting owner
      // verification, hiding it from the owner's queue.
      if (cancelled.affectedRows == 0) return;
      await conn.execute(
        Sql.named('''
        UPDATE bookings
        SET payment_status = 'FAILED', updated_at = NOW()
        WHERE id = @id
        '''),
        parameters: {'id': bookingId},
      );
    });
    return _bookingService.getById(bookingId, viewerId: userId);
  }

  // ---------------------------------------------------------------------
  // Cash on Delivery
  // ---------------------------------------------------------------------

  /// Registers the COD payment for a booking.
  ///
  /// The booking moves to COD_PENDING and RELEASES its slot, so the parking
  /// stays available until the owner confirms the cash. Returns the owner
  /// contact block the user needs ("Please contact your parking owner").
  Future<Map<String, dynamic>> createCod({
    required String bookingId,
    required String userId,
  }) async {
    final before = await _bookingService.getById(bookingId, viewerId: userId);
    final status = before['status'].toString();

    // A booking created straight as COD (POST /api/bookings with
    // paymentMethod=COD) is already COD_PENDING; only the payment row is
    // missing.
    if (status == BookingStatus.codPending) {
      // nothing to transition
    } else if (status == BookingStatus.confirmed ||
        status == BookingStatus.active) {
      throw ApiError.conflict('This booking has already been confirmed.');
    } else {
      await _bookingService.beginCod(bookingId: bookingId, userId: userId);
    }

    final booking = await _bookingService.getById(bookingId, viewerId: userId);
    final ownerId = booking['ownerId'].toString();
    final amount = (booking['amount'] as num).toDouble();
    final reference = _reference();
    final ownerUpi =
        _cleanUpi(booking['ownerUpiIdSnapshot']) ??
        _cleanUpi(booking['ownerUpiId']) ??
        (await _ownerUpiOf(ownerId));

    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('''
        UPDATE payments
        SET payment_status = 'FAILED', updated_at = NOW()
        WHERE booking_id = @bookingId
          AND payment_status IN ('PENDING', 'COD_PENDING')
        '''),
        parameters: {'bookingId': bookingId},
      );
      await conn.execute(
        Sql.named('''
        INSERT INTO payments (
          booking_id, user_id, owner_id, amount, payment_method,
          payment_status, transaction_id, upi_id, reference
        ) VALUES (
          @bookingId, @userId, @ownerId, @amount, 'COD',
          'COD_PENDING', NULL, @upiId, @reference
        )
        '''),
        parameters: {
          'bookingId': bookingId,
          'userId': userId,
          'ownerId': ownerId,
          'amount': amount,
          'upiId': ownerUpi,
          'reference': reference,
        },
      );
      await conn.execute(
        Sql.named('''
        UPDATE bookings
        SET payment_method = 'COD', payment_status = 'COD_PENDING',
            payment_reference = @reference, updated_at = NOW()
        WHERE id = @id
        '''),
        parameters: {'id': bookingId, 'reference': reference},
      );
    });

    final updated = await _bookingService.getById(bookingId, viewerId: userId);
    return {...updated, 'ownerContact': _ownerContact(updated)};
  }

  /// Owner taps "Mark COD Received".
  ///
  /// This is the single gate for the whole COD flow: the slot is allocated,
  /// the booking becomes CONFIRMED, the payment becomes COD_CONFIRMED and
  /// the amount finally enters the owner's Total Earnings.
  ///
  /// Unchanged by the security audit except for the settlement reference: the
  /// server used to invent a `TXN...` "transaction id" here. Cash has no
  /// gateway id at all, so it now records the booking's own `PSK-...`
  /// reference and calls it a settlement reference - nothing is fabricated.
  /// The idempotency and the single-gate guarantee (COD_PENDING only) are
  /// exactly as before.
  Future<Map<String, dynamic>> confirmCod({
    required String bookingId,
    required String ownerId,
  }) async {
    final booking = await _bookingService.getById(bookingId, viewerId: ownerId);
    final status = booking['status'].toString();
    if (status == BookingStatus.confirmed || status == BookingStatus.active) {
      return booking; // idempotent
    }
    if (status != BookingStatus.codPending) {
      throw ApiError.validation(
        'Booking status is $status and cannot be confirmed as cash received.',
      );
    }

    // Allocates the slot and flips the booking to CONFIRMED.
    await _bookingService.confirmCod(bookingId: bookingId, ownerId: ownerId);

    // The booking reference already issued for this payment - the honest
    // settlement record for a cash handover (there is no gateway id).
    final settlementRef =
        _referenceOrNull(booking['paymentReference']) ?? _reference();

    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('''
        UPDATE payments
        SET payment_status = 'COD_CONFIRMED', paid_at = NOW(),
            transaction_id = COALESCE(transaction_id, @ref),
            settled_reference = COALESCE(settled_reference, @ref),
            verified_at = NOW(), verified_by = @ownerId,
            updated_at = NOW()
        WHERE booking_id = @bookingId
          AND payment_method = 'COD'
          AND payment_status = 'COD_PENDING'
        '''),
        parameters: {
          'bookingId': bookingId,
          'ref': settlementRef,
          'ownerId': ownerId,
        },
      );
      await conn.execute(
        Sql.named('''
        UPDATE bookings
        SET cod_confirmed_at = NOW(), cod_confirmed_by = @ownerId,
            updated_at = NOW()
        WHERE id = @id
        '''),
        parameters: {'id': bookingId, 'ownerId': ownerId},
      );
    });

    return _bookingService.getById(bookingId, viewerId: ownerId);
  }

  /// Owner confirms a UPI payment actually reached their account.
  ///
  /// This is the ONLY way a UPI payment becomes `SUCCESS` today, and it is the
  /// exact counterpart of [confirmCod]: the owner is the party who can see the
  /// credit, so the owner is the party that attests to it.
  ///
  /// Security properties:
  ///  * `ownerId` comes from the verified JWT, and [BookingService.settleUpi]
  ///    re-checks `bookings.owner_id`, so a user JWT is rejected with 403;
  ///  * only a booking whose payment is `UPI_PENDING_VERIFICATION` can be
  ///    settled - there is nothing to settle for an un-started payment;
  ///  * it is idempotent: confirming twice counts the earnings once.
  Future<Map<String, dynamic>> settleUpi({
    required String bookingId,
    required String ownerId,
  }) async {
    final booking = await _bookingService.getById(bookingId, viewerId: ownerId);
    final status = booking['status'].toString();
    if (status == BookingStatus.confirmed || status == BookingStatus.active) {
      return booking; // idempotent
    }
    final paymentStatus = booking['paymentStatus'].toString();
    if (paymentStatus != PaymentStatus.upiPendingVerification) {
      throw ApiError.validation(
        'This booking has no UPI payment awaiting verification '
        '(payment status: $paymentStatus).',
      );
    }

    await _bookingService.settleUpi(bookingId: bookingId, ownerId: ownerId);

    final settlementRef =
        _referenceOrNull(booking['paymentReference']) ?? _reference();
    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('''
        UPDATE payments
        SET payment_status = 'SUCCESS', paid_at = NOW(),
            settled_reference = COALESCE(settled_reference, @ref),
            verified_at = NOW(), verified_by = @ownerId,
            updated_at = NOW()
        WHERE booking_id = @bookingId
          AND payment_method = 'UPI'
          AND payment_status = @unverified
        '''),
        parameters: {
          'bookingId': bookingId,
          'unverified': PaymentStatus.upiPendingVerification,
          'ref': settlementRef,
          'ownerId': ownerId,
        },
      );
      await conn.execute(
        Sql.named('''
        UPDATE bookings
        SET upi_verified_at = NOW(), upi_verified_by = @ownerId,
            updated_at = NOW()
        WHERE id = @id
        '''),
        parameters: {'id': bookingId, 'ownerId': ownerId},
      );
    });

    return _bookingService.getById(bookingId, viewerId: ownerId);
  }

  // ---------------------------------------------------------------------
  // Owner earnings summary
  // ---------------------------------------------------------------------
  /// Authoritative, server-computed settlement totals for one owner.
  ///
  /// SECURITY / CORRECTNESS (audit C-02): the Flutter dashboard used to sum
  /// `bookings.amount` for every row whose `paymentStatus` was in the paid set.
  /// That is a client-side derivation of a *money* figure: it silently changes
  /// meaning depending on which page of bookings the client happens to have
  /// fetched (the list endpoints paginate), and the client is the only party
  /// checking it. This method computes the same number in SQL over the whole
  /// owner's booking set, so the app displays what the server believes rather
  /// than re-deriving it.
  ///
  /// The paid set is `('SUCCESS','COD_CONFIRMED')` — exactly
  /// [PaymentStatus.paid]. `UPI_PENDING_VERIFICATION` is therefore excluded by
  /// construction, not by client-side filtering.
  ///
  /// The `ownerId` is always the caller id from the verified JWT, and the query
  /// filters on `bookings.owner_id = @ownerId`, so one owner can never read
  /// another's totals.
  Future<Map<String, dynamic>> ownerEarningsSummary({
    required String ownerId,
  }) async {
    if (!ParkingService.isUuid(ownerId)) {
      throw ApiError.validation('A valid ownerId is required.');
    }

    // In live mode the owner must never see test-mode money as earnings or as
    // something that can be paid out. Test mode still shows it so the audited
    // test payment remains observable for QA; the settlement guard refuses it
    // in both modes.
    final includeTest = Config.razorpayMode != 'live';

    final (res, settlement, entries) = await Db.pool.withConnection((
      conn,
    ) async {
      final earnings = await conn.execute(
        Sql.named('''
        SELECT
          COALESCE(SUM(b.amount) FILTER (
            WHERE b.payment_status IN (@paid1, @paid2)
          ), 0) AS total_earnings,
          COUNT(*) FILTER (
            WHERE b.payment_status IN (@paid1, @paid2)
          ) AS paid_bookings,
          COUNT(*) FILTER (
            WHERE b.payment_status = @codPending
          ) AS cod_pending,
          COUNT(*) FILTER (
            WHERE b.payment_status = @unverified
          ) AS upi_awaiting_verification,
          COUNT(*) FILTER (
            WHERE b.status = @requested
          ) AS pending_requests,
          COUNT(*) FILTER (
            WHERE b.status IN (@confirmed, @active, @paymentPending, @accepted)
          ) AS active_bookings,
          COUNT(*) FILTER (
            WHERE b.status = @completed
          ) AS completed_bookings,
          COUNT(*) AS total_bookings
        FROM bookings b
        WHERE b.owner_id = @ownerId
          AND (
            @includeTest
            OR b.payment_status = @codConfirmed
            OR EXISTS (
              SELECT 1
              FROM payment_transfers pt_live
              JOIN payments p_live ON p_live.id = pt_live.payment_id
              WHERE pt_live.booking_id = b.id
                AND p_live.payment_method = 'RAZORPAY'
                AND p_live.razorpay_mode = 'live'
            )
          )
        '''),
        parameters: {
          'ownerId': ownerId,
          'includeTest': includeTest,
          'paid1': PaymentStatus.success,
          'paid2': PaymentStatus.codConfirmed,
          'codConfirmed': PaymentStatus.codConfirmed,
          'codPending': PaymentStatus.codPending,
          'unverified': PaymentStatus.upiPendingVerification,
          'requested': BookingStatus.requested,
          'confirmed': BookingStatus.confirmed,
          'active': BookingStatus.active,
          'paymentPending': BookingStatus.paymentPending,
          'accepted': BookingStatus.accepted,
          'completed': BookingStatus.completed,
        },
      );

      // Marketplace settlement ledger (Razorpay Route earnings). These are the
      // owner's online-payment shares awaiting settlement. COD is NOT here: the
      // cash is already in the owner's hand, so it is not "pending settlement".
      final settlementAgg = await conn.execute(
        Sql.named('''
        SELECT
          COALESCE(SUM(owner_amount_paise) FILTER (
            WHERE settlement_status <> 'SETTLED'
          ), 0)::bigint AS pending_settlement_paise,
          COALESCE(SUM(owner_amount_paise) FILTER (
            WHERE settlement_status = 'SETTLED'
          ), 0)::bigint AS settled_paise,
          COUNT(*) AS transfer_count
        FROM payment_transfers pt
        JOIN payments p ON p.id = pt.payment_id
        WHERE pt.owner_id = @ownerId
          AND (
            @includeTest
            OR p.payment_method <> 'RAZORPAY'
            OR p.razorpay_mode = 'live'
          )
        '''),
        parameters: {'ownerId': ownerId, 'includeTest': includeTest},
      );

      // A small, newest-first view for the Payments & Settlements screen. The
      // owner only ever sees their own rows (WHERE owner_id = @ownerId).
      final entryRes = await conn.execute(
        Sql.named('''
        SELECT
          pt.booking_id, pl.parking_name,
          pt.gross_amount_paise, pt.platform_fee_paise,
          pt.owner_amount_paise, pt.currency,
          pt.settlement_status, pt.transfer_status, pt.created_at,
          p.payment_status, p.razorpay_payment_id, p.razorpay_mode
        FROM payment_transfers pt
        LEFT JOIN payments p ON p.id = pt.payment_id
        LEFT JOIN bookings b ON b.id = pt.booking_id
        LEFT JOIN parking_listings pl ON pl.id = b.parking_id
        WHERE pt.owner_id = @ownerId
          AND (
            @includeTest
            OR p.payment_method <> 'RAZORPAY'
            OR p.razorpay_mode = 'live'
          )
        ORDER BY pt.created_at DESC
        LIMIT 20
        '''),
        parameters: {'ownerId': ownerId, 'includeTest': includeTest},
      );

      return (earnings, settlementAgg, entryRes);
    });

    final row = res.isEmpty
        ? const <String, Object?>{}
        : res.first.toColumnMap();
    double d(Object? v) => v is num ? v.toDouble() : 0;

    // AUDIT: `SUM()` over a bigint column returns PostgreSQL `numeric`, and
    // the driver ALWAYS decodes `numeric` as a STRING. A naive
    // `v is num ? v.toInt() : 0` therefore reported every settlement total as
    // 0 (the owner could never see that an earning had been settled). Parse
    // the textual form as well, exactly like the other services do.
    int i(Object? v) {
      if (v is num) return v.toInt();
      final asInt = int.tryParse('$v');
      if (asInt != null) return asInt;
      return double.tryParse('$v')?.toInt() ?? 0;
    }

    final settlementRow = settlement.isEmpty
        ? const <String, Object?>{}
        : settlement.first.toColumnMap();

    final settlementEntries = <Map<String, dynamic>>[
      for (final r in entries)
        () {
          final m = r.toColumnMap();
          return {
            'bookingId': m['booking_id']?.toString(),
            'parkingName': m['parking_name']?.toString() ?? '',
            'grossAmountPaise': i(m['gross_amount_paise']),
            'platformFeePaise': i(m['platform_fee_paise']),
            'ownerAmountPaise': i(m['owner_amount_paise']),
            'currency': m['currency']?.toString() ?? 'INR',
            'settlementStatus': m['settlement_status']?.toString() ?? 'PENDING',
            'transferStatus': m['transfer_status']?.toString() ?? 'PENDING',
            'paymentStatus': m['payment_status']?.toString() ?? '',
            'razorpayPaymentId': m['razorpay_payment_id']?.toString(),
            'razorpayMode': m['razorpay_mode']?.toString(),
            'createdAt': m['created_at']?.toString(),
          };
        }(),
    ];

    return {
      'ownerId': ownerId,
      'totalEarnings': d(row['total_earnings']),
      'paidBookings': i(row['paid_bookings']),
      'codPending': i(row['cod_pending']),
      'upiAwaitingVerification': i(row['upi_awaiting_verification']),
      'pendingRequests': i(row['pending_requests']),
      'activeBookings': i(row['active_bookings']),
      'completedBookings': i(row['completed_bookings']),
      'totalBookings': i(row['total_bookings']),
      // Marketplace settlement ledger totals (integer paise). `settlement` is
      // PENDING until a provider transfer or a recorded manual payout occurs.
      'pendingSettlementPaise': i(settlementRow['pending_settlement_paise']),
      'settledPaise': i(settlementRow['settled_paise']),
      'transferCount': i(settlementRow['transfer_count']),
      'settlementEntries': settlementEntries,
      // Tells the client this figure is the server's, not a client derivation.
      'source': 'server',
      'paidStatuses': [PaymentStatus.success, PaymentStatus.codConfirmed],
    };
  }

  // ---------------------------------------------------------------------
  // Legacy combined endpoint (POST /api/payments)
  // ---------------------------------------------------------------------
  /// Backward-compatible entry point kept so an older client build keeps
  /// working. It simply dispatches to the same internal logic used by the
  /// dedicated endpoints - no duplicated payment rules.
  ///
  /// SECURITY (audit C-01): the old version of this method called
  /// `confirmUpi(transactionId: _transactionId())` when the client sent no id,
  /// i.e. it fabricated a gateway reference so that a client which never
  /// opened a UPI app still ended up with a `SUCCESS` payment. It now forwards
  /// only what the client actually sent, which means a legacy client that skips
  /// the `/upi/intent` step receives `409` instead of a paid booking. That is
  /// the intended behaviour: no legitimate flow needs the old one.
  Future<Map<String, dynamic>> create({
    required String userId,
    required Map<String, dynamic> body,
  }) async {
    final bookingId = body['bookingId']?.toString() ?? '';
    if (bookingId.isEmpty) throw ApiError.validation('bookingId is required.');
    final method = _normalizeMethod(body['paymentMethod']?.toString());
    if (method == PaymentMethod.cod) {
      return createCod(bookingId: bookingId, userId: userId);
    }
    return confirmUpi(
      bookingId: bookingId,
      userId: userId,
      transactionId: body['transactionId']?.toString(),
      reference: body['reference']?.toString(),
      rawResponse: body['rawResponse'] is Map<String, dynamic>
          ? body['rawResponse'] as Map<String, dynamic>
          : null,
    );
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  /// Loads a booking the caller is allowed to pay for and asserts it is in a
  /// payable state. Keeps the old "owner approval first" rule intact.
  Future<Map<String, dynamic>> _payableBooking(
    String bookingId, {
    required String viewerId,
  }) async {
    final booking = await _bookingService.getById(
      bookingId,
      viewerId: viewerId,
    );
    final status = booking['status'].toString();
    if (status == BookingStatus.requested ||
        status == BookingStatus.rejected ||
        status == BookingStatus.cancelled) {
      throw ApiError.validation(
        'Payment requires owner approval first (booking is $status).',
      );
    }
    final amount = (booking['amount'] as num?)?.toDouble();
    if (amount == null || amount <= 0) {
      throw ApiError.server('Booking amount is missing.');
    }
    return booking;
  }

  /// Owner contact block shown to the user on the COD screen.
  static Map<String, dynamic> _ownerContact(Map<String, dynamic> booking) => {
    'name': booking['ownerName']?.toString() ?? '',
    'phone': _cleanPhone(booking['ownerPhone']),
    'upiId': _cleanUpi(booking['ownerUpiId']),
    'parkingName':
        (booking['parking'] is Map
            ? (booking['parking'] as Map)['name']?.toString()
            : null) ??
        '',
    'address':
        (booking['parking'] is Map
            ? (booking['parking'] as Map)['address']?.toString()
            : null) ??
        '',
  };

  /// Only UPI and COD. Card / NetBanking / anything unknown fall back to UPI
  /// so an old client never dead-ends on a validation error.
  String _normalizeMethod(String? raw) {
    final value = (raw ?? '').trim().toUpperCase();
    return PaymentMethod.all.contains(value) ? value : PaymentMethod.upi;
  }

  Future<String?> _ownerUpiOf(String ownerId) async {
    if (!ParkingService.isUuid(ownerId)) return null;
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT upi_id FROM users WHERE id = @id'),
        parameters: {'id': ownerId},
      );
    });
    if (res.isEmpty) return null;
    return _cleanUpi(res.first.toColumnMap()['upi_id']);
  }

  /// UPI virtual payment address, normalised, or null when missing/invalid.
  static String? _cleanUpi(Object? raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    if (value.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9._-]{2,64}$')
        .hasMatch(value)) {
      return null;
    }
    return value;
  }

  static String? _cleanPhone(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final ch = value[i];
      if (ch == '+' && buffer.isEmpty) {
        buffer.write(ch);
      } else if (RegExp(r'[0-9]').hasMatch(ch)) {
        buffer.write(ch);
      }
    }
    final digits = buffer.toString();
    if (digits.isEmpty || digits == '+') return null;
    return digits;
  }

  /// Human-friendly note shown inside the UPI app.
  static String _note(String reference, String parkingName) {
    final where = parkingName.isEmpty ? 'ParkShare' : 'ParkShare $parkingName';
    return '$where booking $reference';
  }

  /// Short booking reference, e.g. `PSK-4F2A9C31`.
  ///
  /// This is a ParkShare reference, NOT a gateway transaction id, and it is
  /// only ever generated for a payment attempt this server created.
  String _reference() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final buf = StringBuffer('PSK-');
    for (var i = 0; i < _bookingIdLength; i++) {
      buf.write(chars[_random.nextInt(chars.length)]);
    }
    return buf.toString();
  }

  /// Reuses an already-issued reference when the row has one, else null.
  static String? _referenceOrNull(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }
}
