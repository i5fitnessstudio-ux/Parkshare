import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/booking.dart';
import 'package:parkshare_backend/models/parking.dart';
import 'package:parkshare_backend/services/parking_service.dart';
import 'package:parkshare_backend/services/parking_space_service.dart';
import 'package:postgres/postgres.dart';

/// Booking domain service: create (with slot allocation + conflict + fit
/// checks), owner/user list, detail (joined), accept/reject.
class BookingService {
  /// Slot-based allocation. A booking always holds ONE physical space.
  final ParkingSpaceService _spaces = ParkingSpaceService();

  /// Creates a booking. Server-side validates:
  ///  - parking exists, available, not owned by the requester
  ///  - vehicle belongs to requester, matches type, fits the gate
  ///  - rental option enabled, dates valid
  ///  - a FREE PARKING SLOT of the right type fits the vehicle for the window
  ///    (one booked slot never blocks the whole property)
  ///
  /// [paymentMethod] is `UPI` (default) or `COD`:
  ///  * UPI — slot is allocated and the booking waits for the payment
  ///    confirmation, which flips it to CONFIRMED.
  ///  * COD — the booking is created as COD_PENDING and the slot is verified
  ///    but NOT held, so the parking stays available until the owner confirms
  ///    the cash. The slot is then allocated by the COD confirmation.
  ///
  /// Returns joined payload; status = REQUESTED (or ACCEPTED when the
  /// parking uses auto-approval), COD_PENDING for cash bookings.
  Future<Map<String, dynamic>> create({
    required String userId,
    required Map<String, dynamic> body,
  }) async {
    final parkingId = body['parkingId']?.toString() ?? '';
    final vehicleId = body['vehicleId']?.toString() ?? '';
    final rentalType = body['rentalType']?.toString().toUpperCase() ?? '';
    final startDate = _parseDate(body['startDate'], 'startDate');
    final endDate = _parseDate(body['endDate'], 'endDate');
    final paymentMethod = _normalizePaymentMethod(
      body['paymentMethod']?.toString(),
    );

    if (parkingId.isEmpty || vehicleId.isEmpty) {
      throw ApiError.validation('parkingId and vehicleId are required.');
    }
    if (!RentalType.all.contains(rentalType)) {
      throw ApiError.validation('rentalType must be MONTHLY or YEARLY.');
    }
    if (endDate.isBefore(startDate)) {
      throw ApiError.validation('endDate must be on or after startDate.');
    }
    if (endDate.difference(startDate).inDays > 366) {
      throw ApiError.validation('Booking cannot exceed 12 months (366 days).');
    }

    final parkingRow = await _parkingRow(parkingId);
    if (parkingRow == null) {
      throw ApiError.notFound('Parking listing not found.');
    }
    // A listing soft-deleted by account deletion (or anything else) can never
    // be booked again, even though `_parkingRow` itself stays unfiltered so
    // existing bookings can still render the historical row.
    if (parkingRow['deleted_at'] != null) {
      throw ApiError.notFound('Parking listing not found.');
    }
    if (parkingRow['owner_id'].toString() == userId) {
      throw ApiError.validation('You cannot book your own parking.');
    }
    if (parkingRow['available'] != true) {
      throw ApiError.validation('This parking is not currently available.');
    }

    final vehicleRow = await _vehicleRow(vehicleId);
    if (vehicleRow == null || vehicleRow['user_id'].toString() != userId) {
      throw ApiError.validation('Vehicle not found or does not belong to you.');
    }

    // Vehicle-type compatibility (BIKE/CAR/BOTH).
    final parkingVt = parkingRow['vehicle_type'].toString();
    final vehicleVt = vehicleRow['vehicle_type'].toString();
    if (!ParkingService.vehicleAllowed(parkingVt, vehicleVt)) {
      throw ApiError.validation(
        'This parking does not accept ${vehicleVt == 'BIKE' ? 'bikes' : 'cars'}.',
      );
    }

    final vehicleLengthM = _d(vehicleRow['length_m']);
    final vehicleWidthM = _d(vehicleRow['width_m']);
    final vehicleHeightM = _d(vehicleRow['height_m']);

    // Rental option + amount (always derived server-side from the listing).
    // Plans are per vehicle type (car/bike x monthly/yearly); a listing saved
    // before migration 006 (per_vehicle_plans = FALSE) shares one pair for
    // both types, so a legacy listing still books exactly as it used to.
    final planPrefix = parkingRow['per_vehicle_plans'] == true
        ? '${vehicleVt == 'BIKE' ? 'bike' : 'car'}_'
        : '';
    final label = vehicleVt == 'BIKE' ? 'bikes' : 'cars';
    final double amount;
    if (rentalType == RentalType.monthly) {
      if (parkingRow['${planPrefix}monthly_enabled'] != true) {
        throw ApiError.validation(
          'This parking does not offer monthly rentals for $label.',
        );
      }
      amount = _d(parkingRow['${planPrefix}monthly_rent']);
    } else {
      if (parkingRow['${planPrefix}yearly_enabled'] != true) {
        throw ApiError.validation(
          'This parking does not offer yearly rentals for $label.',
        );
      }
      amount = _d(parkingRow['${planPrefix}yearly_rent']);
    }

    final autoApproval = parkingRow['auto_approval'] == true;
    // Cash on Delivery short-circuits the request/accept step: the user is
    // going to pay the owner directly, so the only thing the owner has to do
    // is confirm the cash. UPI keeps the existing REQUESTED / ACCEPTED flow.
    final isCod = paymentMethod == PaymentMethod.cod;
    final status = isCod
        ? BookingStatus.codPending
        : autoApproval
        ? BookingStatus.accepted
        : BookingStatus.requested;
    final paymentStatus = isCod
        ? PaymentStatus.codPending
        : PaymentStatus.pending;
    final ownerId = parkingRow['owner_id'].toString();
    // Snapshot the owner's UPI id right now: this is the address the payment
    // must reach, even if the owner edits it later.
    final ownerUpiId = _cleanUpi((await _userRow(ownerId))?['upi_id']);

    // Authoritative slot allocation + INSERT run inside ONE transaction and
    // under a row lock on the parking listing, so two concurrent requests can
    // never be handed the same slot for overlapping dates. A database-level
    // EXCLUDE constraint on (parking_space_id, date range) is the final
    // backstop.
    final String bookingId;
    final String spaceCode;
    try {
      final result = await Db.pool.withConnection((conn) async {
        return conn.runTx((tx) async {
          // Serialise every booking write for this parking.
          final locked = await tx.execute(
            Sql.named(
              'SELECT id FROM parking_listings WHERE id = @id FOR UPDATE',
            ),
            parameters: {'id': parkingId},
          );
          if (locked.isEmpty) {
            throw ApiError.notFound('Parking listing not found.');
          }

          final allocation = await _spaces.allocate(
            parkingId: parkingId,
            vehicleType: vehicleVt,
            vehicleLengthM: vehicleLengthM,
            vehicleWidthM: vehicleWidthM,
            vehicleHeightM: vehicleHeightM,
            start: startDate,
            end: endDate,
            conn: tx,
          );

          switch (allocation.outcome) {
            case SlotOutcome.noFit:
              throw ApiError.validation(
                'Your vehicle may not fit this parking space.',
              );
            case SlotOutcome.full:
              throw ApiError.conflict(_fullMessage(vehicleVt));
            case SlotOutcome.allocated:
              break;
          }

          final spaceId = allocation.space!['id'].toString();
          final code = allocation.space!['space_code'].toString();

          final res = await tx.execute(
            Sql.named('''
            INSERT INTO bookings (
              parking_id, parking_space_id, user_id, owner_id, vehicle_id,
              rental_type, start_date, end_date, amount, status,
              payment_method, payment_status, owner_upi_id_snapshot
            ) VALUES (
              @parkingId, @spaceId, @userId, @ownerId, @vehicleId,
              @rentalType, @startDate, @endDate, @amount, @status,
              @paymentMethod, @paymentStatus, @ownerUpiId
            )
            RETURNING id
            '''),
            parameters: {
              'parkingId': parkingId,
              // COD_PENDING must NOT hold the slot: the cash has not been paid
              // yet, so the space stays available to other users. The slot is
              // allocated when the owner confirms the cash.
              'spaceId': isCod ? null : spaceId,
              'userId': userId,
              'ownerId': ownerId,
              'vehicleId': vehicleId,
              'rentalType': rentalType,
              'startDate': startDate,
              'endDate': endDate,
              'amount': amount,
              'status': status,
              'paymentMethod': paymentMethod,
              'paymentStatus': paymentStatus,
              'ownerUpiId': ownerUpiId,
            },
          );
          final id = res.first.toColumnMap()['id']!.toString();
          await _appendHistory(tx, id, status);
          return (id: id, code: code);
        });
      });
      bookingId = result.id;
      spaceCode = result.code;
    } on ServerException catch (e) {
      // A serialisation failure or the exclusion-constraint violation under
      // concurrent writes is still a conflict from the caller's point of view.
      if (e.code == '40001' || e.code == '23505' || e.code == '23P01') {
        throw ApiError.conflict(
          'Another user just took that parking space. Please try again.',
        );
      }
      rethrow;
    }

    final booking = await _getJoined(bookingId);
    return {...booking, 'allocatedSpaceCode': spaceCode};
  }

  /// Slot availability probe used by the booking form and the parking detail
  /// screen BEFORE the final submit (UX only). [create] remains the
  /// authoritative guard against double bookings.
  Future<Map<String, dynamic>> availability({
    required String parkingId,
    required DateTime startDate,
    required DateTime endDate,
    String? vehicleId,
    String? vehicleType,
    double? vehicleLengthM,
    double? vehicleWidthM,
    double? vehicleHeightM,
  }) async {
    if (endDate.isBefore(startDate)) {
      throw ApiError.validation('endDate must be on or after startDate.');
    }
    final parking = await _parkingRow(parkingId);
    if (parking == null) throw ApiError.notFound('Parking listing not found.');

    // A vehicleId wins: the server then uses the saved vehicle type AND its
    // real dimensions for the fit check.
    var type = vehicleType?.toUpperCase();
    if (vehicleId != null && vehicleId.isNotEmpty) {
      final vehicle = await _vehicleRow(vehicleId);
      if (vehicle != null) {
        type = vehicle['vehicle_type']?.toString().toUpperCase();
        vehicleLengthM ??= _d(vehicle['length_m']);
        vehicleWidthM ??= _d(vehicle['width_m']);
        vehicleHeightM ??= _d(vehicle['height_m']);
      }
    }
    if (!ParkingVehicleType.all.contains(type ?? '')) {
      type = null;
    }

    return _spaces.availability(
      parkingId: parkingId,
      start: startDate,
      end: endDate,
      vehicleType: type,
      vehicleLengthM: vehicleLengthM,
      vehicleWidthM: vehicleWidthM,
      vehicleHeightM: vehicleHeightM,
    );
  }

  /// Customer-facing "full" copy, per vehicle type (PART 18/35).
  static String _fullMessage(String vehicleType) => vehicleType == 'BIKE'
      ? 'Bike Parking Full. This parking has no bike spaces available for '
            'your selected dates. Please choose different dates or another '
            'parking location.'
      : 'Car Parking Full. This parking has no car spaces available for '
            'your selected dates. Please choose different dates or another '
            'parking location.';

  /// Short "Bike/Car Parking" prefix used when the sentence is followed by the
  /// owner's own next step.
  static String _fullShortLabel(String vehicleType) =>
      vehicleType == 'BIKE' ? 'Bike Parking' : 'Car Parking';

  /// Owner dashboard + booking tab list.
  Future<List<Map<String, dynamic>>> listByOwner(String ownerId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT * FROM bookings WHERE owner_id = @ownerId
        ORDER BY created_at DESC
        '''),
        parameters: {'ownerId': ownerId},
      );
    });
    return _joinRows(res.map((r) => r.toColumnMap()).toList());
  }

  /// Vehicle user's booking history.
  Future<List<Map<String, dynamic>>> listByUser(String userId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT * FROM bookings WHERE user_id = @userId
        ORDER BY created_at DESC
        '''),
        parameters: {'userId': userId},
      );
    });
    return _joinRows(res.map((r) => r.toColumnMap()).toList());
  }

  Future<Map<String, dynamic>> getById(
    String bookingId, {
    required String viewerId,
  }) async {
    final row = await _bookingRow(bookingId);
    if (row == null) throw ApiError.notFound('Booking not found.');
    if (row['user_id'].toString() != viewerId &&
        row['owner_id'].toString() != viewerId) {
      throw ApiError.forbidden('You do not have access to this booking.');
    }
    final list = await _joinRows([row]);
    return list.first;
  }

  /// Statuses that actually reserve the parking live in the model
  /// (`occupyingStatusList`) so the slot engine and the booking service can
  /// never drift apart.

  /// Owner accepts a request. The slot is re-verified (and re-allocated when
  /// needed) inside the same transaction as the status change, because a
  /// REQUESTED booking does not reserve capacity: another accepted booking may
  /// have taken the promised slot in the meantime.
  Future<Map<String, dynamic>> accept({
    required String bookingId,
    required String ownerId,
  }) async {
    return _transition(
      bookingId: bookingId,
      ownerId: ownerId,
      from: {BookingStatus.requested},
      to: BookingStatus.accepted,
      reserveSlot: true,
    );
  }

  Future<Map<String, dynamic>> reject({
    required String bookingId,
    required String ownerId,
  }) async {
    return _transition(
      bookingId: bookingId,
      ownerId: ownerId,
      from: {BookingStatus.requested, BookingStatus.accepted},
      to: BookingStatus.rejected,
    );
  }

  /// Owner confirms the cash was received for a COD booking.
  ///
  /// This is the ONLY thing that turns a cash booking into a real one: the
  /// slot is allocated here (so the parking becomes booked / unavailable) and
  /// the status moves to CONFIRMED, which is what adds the amount to the
  /// owner's Total Earnings. Before this, a COD_PENDING booking is invisible
  /// to availability and earnings by design.
  Future<Map<String, dynamic>> confirmCod({
    required String bookingId,
    required String ownerId,
  }) async {
    return _transition(
      bookingId: bookingId,
      ownerId: ownerId,
      from: {BookingStatus.codPending},
      to: BookingStatus.confirmed,
      reserveSlot: true,
      paymentStatus: PaymentStatus.codConfirmed,
    );
  }

  /// Owner confirms a UPI payment they can see in their own account.
  ///
  /// SECURITY (audit C-01): a `upi://` intent gives the server no proof that
  /// money moved, so a UPI payment can only reach CONFIRMED through an
  /// explicit owner attestation — the same trust model as
  /// [confirmCod]. `_transition` re-checks `bookings.owner_id` against
  /// [ownerId], so a vehicle-user JWT can never settle another owner's
  /// payment.
  ///
  /// The slot is deliberately NOT re-allocated (`reserveSlot: false`): an
  /// ACCEPTED / PAYMENT_PENDING booking already holds its space, and the
  /// database-level overlap constraint keeps it that way.
  Future<Map<String, dynamic>> settleUpi({
    required String bookingId,
    required String ownerId,
  }) async {
    return _transition(
      bookingId: bookingId,
      ownerId: ownerId,
      from: {BookingStatus.accepted, BookingStatus.paymentPending},
      to: BookingStatus.confirmed,
      reserveSlot: false,
      paymentStatus: PaymentStatus.success,
    );
  }

  /// Confirms a booking because a **verified** online (Razorpay) payment was
  /// received.
  ///
  /// Unlike [confirmCod] / [settleUpi] there is no owner JWT in the webhook
  /// path, so this is an internal, service-only transition. It is only ever
  /// called by [RazorpayPaymentService] AFTER the gateway signature (or webhook
  /// HMAC) has been verified; it never trusts a client assertion.
  ///
  /// Safety:
  ///   * idempotent — an already CONFIRMED / ACTIVE booking is returned as-is;
  ///   * refuses COD_PENDING / REQUESTED / REJECTED / CANCELLED bookings, so an
  ///     online payment can never hijack a cash or unapproved booking;
  ///   * the slot is not re-allocated (an ACCEPTED / PAYMENT_PENDING booking
  ///     already holds its space, exactly like [settleUpi]).
  Future<Map<String, dynamic>> confirmOnlinePayment({
    required String bookingId,
  }) async {
    await Db.pool.withConnection((conn) async {
      await conn.runTx((tx) async {
        await confirmOnlinePaymentInTransaction(tx, bookingId: bookingId);
      });
    });

    return _getJoined(bookingId);
  }

  /// Transaction-scoped form of [confirmOnlinePayment].
  ///
  /// RazorpayPaymentService must update the payment row, the booking row and
  /// the owner ledger in ONE transaction. If the booking is no longer payable
  /// (for example it was cancelled while Checkout was open), every write must
  /// roll back; otherwise the ledger could report money for a booking that was
  /// never confirmed.
  ///
  /// [tx] is a `postgres` transaction/session. The booking row is locked
  /// `FOR UPDATE` before its status is inspected, so a concurrent cancellation
  /// or owner action cannot slip between the check and the update.
  ///
  /// This is still service-only: callers must already have verified the
  /// gateway HMAC. It never accepts a client-authored \"paid\" assertion.
  Future<void> confirmOnlinePaymentInTransaction(
    dynamic tx, {
    required String bookingId,
  }) async {
    final res = await tx.execute(
      Sql.named('''
      SELECT status, payment_method, payment_status
      FROM bookings
      WHERE id = @id
      FOR UPDATE
      '''),
      parameters: {'id': bookingId},
    );
    if (res.isEmpty) throw ApiError.notFound('Booking not found.');

    final row = res.first.toColumnMap();
    final current = row['status']?.toString() ?? '';
    if (current == BookingStatus.confirmed || current == BookingStatus.active) {
      // Idempotent: a webhook and Checkout verification can both report the
      // same captured payment. Heal the mirror if an older workflow stopped
      // between the two writes, but never touch a COD booking.
      if (row['payment_method']?.toString() != 'COD') {
        await tx.execute(
          Sql.named('''
          UPDATE bookings
          SET payment_status = @paymentStatus, updated_at = NOW()
          WHERE id = @id
          '''),
          parameters: {'paymentStatus': PaymentStatus.success, 'id': bookingId},
        );
      }
      return;
    }
    if (current != BookingStatus.accepted &&
        current != BookingStatus.paymentPending) {
      throw ApiError.conflict(
        'Booking status is $current and cannot be confirmed by an online '
        'payment. No payment was recorded; the gateway payment needs manual '
        'review or refund.',
      );
    }

    // Guarded UPDATE: only one concurrent caller can flip the booking. The row
    // is already locked above, but keeping the predicate makes the operation
    // safe even if this helper is ever called without the lock.
    final updated = await tx.execute(
      Sql.named('''
      UPDATE bookings
      SET status = @to, payment_status = @paymentStatus,
          payment_method = 'RAZORPAY', updated_at = NOW()
      WHERE id = @id
        AND status IN (@accepted, @paymentPending)
      '''),
      parameters: {
        'to': BookingStatus.confirmed,
        'paymentStatus': PaymentStatus.success,
        'id': bookingId,
        'accepted': BookingStatus.accepted,
        'paymentPending': BookingStatus.paymentPending,
      },
    );
    if (updated.affectedRows != 1) {
      throw ApiError.conflict(
        'Booking changed while the payment was being confirmed. No payment '
        'was recorded; the gateway payment needs manual review or refund.',
      );
    }
    await _appendHistory(tx, bookingId, BookingStatus.confirmed);
  }

  /// Re-checks (and when needed allocates) a free, big-enough slot for a
  /// booking that is about to start occupying capacity. Runs under a row lock
  /// on the listing, so two owners' clicks can never hand the same slot to two
  /// bookings. Exposed for the payment service (COD confirmation).
  Future<void> reserveSlotForBooking(String bookingId) async {
    final row = await _bookingRow(bookingId);
    if (row == null) throw ApiError.notFound('Booking not found.');
    if (row['parking_space_id'] != null) return; // already holds one
    await _reserveSlotForAccept(row);
  }

  /// Switches an approved booking to Cash on Delivery.
  ///
  /// The slot is deliberately RELEASED (`parking_space_id = NULL`): the user
  /// has chosen cash but has not paid, so the space must keep showing as
  /// available. It is re-allocated by [confirmCod] when the owner confirms the
  /// cash. Idempotent for a booking that is already COD_PENDING.
  Future<Map<String, dynamic>> beginCod({
    required String bookingId,
    required String userId,
  }) async {
    final row = await _bookingRow(bookingId);
    if (row == null) throw ApiError.notFound('Booking not found.');
    if (row['user_id'].toString() != userId) {
      throw ApiError.forbidden('You can only pay for your own booking.');
    }
    final current = row['status'].toString();
    if (current == BookingStatus.codPending) {
      final existing = await _joinRows([row]);
      return existing.first;
    }
    if (current == BookingStatus.confirmed || current == BookingStatus.active) {
      throw ApiError.conflict('This booking has already been confirmed.');
    }
    if (current != BookingStatus.accepted &&
        current != BookingStatus.paymentPending) {
      throw ApiError.validation(
        'Booking is $current and cannot be paid as cash yet.',
      );
    }

    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('''
        UPDATE bookings
        SET status = @status, parking_space_id = NULL,
            payment_method = 'COD', payment_status = 'COD_PENDING',
            updated_at = NOW()
        WHERE id = @id
        '''),
        parameters: {'id': bookingId, 'status': BookingStatus.codPending},
      );
      await _appendHistory(conn, bookingId, BookingStatus.codPending);
    });
    final updated = await _bookingRow(bookingId);
    if (updated == null) {
      throw ApiError.server('Booking could not be reloaded.');
    }
    final list = await _joinRows([updated]);
    return list.first;
  }

  Future<Map<String, dynamic>> _transition({
    required String bookingId,
    required String ownerId,
    required Set<String> from,
    required String to,
    bool reserveSlot = false,
    String? paymentStatus,
  }) async {
    final row = await _bookingRow(bookingId);
    if (row == null) throw ApiError.notFound('Booking not found.');
    if (row['owner_id'].toString() != ownerId) {
      throw ApiError.forbidden('Only the parking owner can do that.');
    }
    final current = row['status'].toString();
    if (!from.contains(current)) {
      throw ApiError.conflict(
        'Booking status is $current and cannot be changed to $to.',
      );
    }

    if (reserveSlot) {
      await _reserveSlotForAccept(row);
    }

    await Db.pool.withConnection((conn) async {
      if (paymentStatus == null) {
        await conn.execute(
          Sql.named('''
          UPDATE bookings SET status = @to, updated_at = NOW()
          WHERE id = @id
          '''),
          parameters: {'id': bookingId, 'to': to},
        );
      } else {
        await conn.execute(
          Sql.named('''
          UPDATE bookings
          SET status = @to, payment_status = @paymentStatus, updated_at = NOW()
          WHERE id = @id
          '''),
          parameters: {
            'id': bookingId,
            'to': to,
            'paymentStatus': paymentStatus,
          },
        );
      }
      await _appendHistory(conn, bookingId, to);
    });
    final updated = await _bookingRow(bookingId);
    if (updated == null) {
      throw ApiError.server('Booking could not be reloaded.');
    }
    final list = await _joinRows([updated]);
    return list.first;
  }

  /// Makes sure the booking holds a free, big-enough slot at the moment the
  /// owner accepts it. Runs under a row lock on the listing, so two owners'
  /// clicks can never hand the same slot to two bookings.
  ///
  /// The slot the customer was promised is kept whenever it is still free and
  /// still fits; otherwise another suitable slot is taken. Legacy bookings
  /// (no slot at all) get one here.
  Future<void> _reserveSlotForAccept(Map<String, dynamic> row) async {
    final parkingId = row['parking_id'].toString();
    final vehicleId = row['vehicle_id'].toString();
    final start = row['start_date'];
    final end = row['end_date'];
    if (start is! DateTime || end is! DateTime) {
      throw ApiError.server('Booking dates are invalid.');
    }
    final vehicle = await _vehicleRow(vehicleId);
    if (vehicle == null) {
      throw ApiError.validation('Vehicle not found for this booking.');
    }
    final vehicleVt = vehicle['vehicle_type'].toString();

    try {
      await Db.pool.withConnection((conn) async {
        await conn.runTx((tx) async {
          final locked = await tx.execute(
            Sql.named(
              'SELECT id FROM parking_listings WHERE id = @id FOR UPDATE',
            ),
            parameters: {'id': parkingId},
          );
          if (locked.isEmpty) {
            throw ApiError.notFound('Parking listing not found.');
          }

          final allocation = await _spaces.allocate(
            parkingId: parkingId,
            vehicleType: vehicleVt,
            vehicleLengthM: _d(vehicle['length_m']),
            vehicleWidthM: _d(vehicle['width_m']),
            vehicleHeightM: _d(vehicle['height_m']),
            start: start,
            end: end,
            preferredSpaceId: row['parking_space_id']?.toString(),
            conn: tx,
          );

          switch (allocation.outcome) {
            case SlotOutcome.noFit:
              throw ApiError.conflict(
                'This vehicle no longer fits any free parking space in this '
                'listing. Please reject the request or ask the customer to '
                'update their vehicle details.',
              );
            case SlotOutcome.full:
              throw ApiError.conflict(
                '${_fullShortLabel(vehicleVt)} is full for the requested dates, '
                'so this request can no longer be accepted. Please reject it or '
                'ask the customer to choose different dates.',
              );
            case SlotOutcome.allocated:
              break;
          }

          await tx.execute(
            Sql.named('''
            UPDATE bookings
            SET parking_space_id = @spaceId, updated_at = NOW()
            WHERE id = @id
            '''),
            parameters: {
              'spaceId': allocation.space!['id'].toString(),
              'id': row['id'].toString(),
            },
          );
        });
      });
    } on ServerException catch (e) {
      if (e.code == '40001' || e.code == '23505' || e.code == '23P01') {
        throw ApiError.conflict(
          'That parking space was just taken. Please reject the request or ask '
          'the customer to choose different dates.',
        );
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Future<void> _appendHistory(
    dynamic conn,
    String bookingId,
    String status,
  ) async {
    await conn.execute(
      Sql.named('''
      INSERT INTO booking_status_history (booking_id, status)
      VALUES (@bookingId, @status)
      '''),
      parameters: {'bookingId': bookingId, 'status': status},
    );
  }

  Future<List<Map<String, dynamic>>> _joinRows(
    List<Map<String, dynamic>> bookingRows,
  ) async {
    if (bookingRows.isEmpty) return const [];
    final out = <Map<String, dynamic>>[];
    for (final b in bookingRows) {
      final parking = await _parkingRow(b['parking_id'].toString());
      final user = await _userRow(b['user_id'].toString());
      // The parking owner of THIS booking (booking.owner_id, falling back to
      // parking.owner_id), never a global owner: booking A always resolves to
      // owner A and owner A's phone number.
      final bookingOwnerId = b['owner_id']?.toString() ?? '';
      final owner = await _userRow(
        bookingOwnerId.isNotEmpty
            ? bookingOwnerId
            : parking?['owner_id']?.toString(),
      );
      final vehicle = await _vehicleRow(b['vehicle_id'].toString());
      final payment = await _latestPayment(b['id'].toString());
      if (payment != null) {
        // Expose Razorpay payment id on the booking JSON without changing the
        // booking table shape; the receipt must not conflate it with the
        // booking/reference id.
        if ((payment['razorpay_payment_id']?.toString() ?? '').isNotEmpty) {
          b['razorpay_payment_id'] = payment['razorpay_payment_id'];
        }
      }
      final photos = await _parkingPhotos(b['parking_id'].toString());
      final spaceId = b['parking_space_id']?.toString();
      final space = (spaceId == null || spaceId.isEmpty)
          ? null
          : await _spaceRow(spaceId);
      out.add(
        bookingJoinedJson(
          bookingRow: b,
          userRow: user,
          parkingRow: parking,
          vehicleRow: vehicle,
          ownerRow: owner,
          paymentRow: payment,
          parkingSpaceRow: space,
          photoUrls: photos,
        ),
      );
    }
    return out;
  }

  Future<Map<String, dynamic>?> _parkingRow(String id) async {
    if (!_isUuid(id)) return null;
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT * FROM parking_listings WHERE id = @id'),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  Future<Map<String, dynamic>?> _vehicleRow(String id) async {
    if (!_isUuid(id)) return null;
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT * FROM vehicles WHERE id = @id'),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  /// The `parking_spaces` row a booking holds, for the space code shown on
  /// both the owner and the user booking card.
  Future<Map<String, dynamic>?> _spaceRow(String id) async {
    if (!_isUuid(id)) return null;
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT * FROM parking_spaces WHERE id = @id'),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  /// `id` columns are UUIDs — a non-UUID value is "not found", not a 500 from
  /// Postgres ("invalid input syntax for type uuid").
  static bool _isUuid(String id) => ParkingService.isUuid(id);

  Future<Map<String, dynamic>?> _userRow(String? id) async {
    if (id == null || id.isEmpty) return null;
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named(
          'SELECT id, name, phone, upi_id, role FROM users WHERE id = @id',
        ),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  Future<Map<String, dynamic>?> _bookingRow(String id) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT * FROM bookings WHERE id = @id'),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  Future<Map<String, dynamic>?> _latestPayment(String bookingId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT * FROM payments WHERE booking_id = @id
        ORDER BY created_at DESC LIMIT 1
        '''),
        parameters: {'id': bookingId},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  Future<List<String>> _parkingPhotos(String parkingId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT url FROM parking_media WHERE parking_id = @id
        ORDER BY display_order ASC LIMIT 3
        '''),
        parameters: {'id': parkingId},
      );
    });
    return res.map((r) => r.toColumnMap()['url'].toString()).toList();
  }

  /// Re-fetches a booking by its own id and returns the fully joined payload
  /// (user + owner + parking + vehicle + payment) after create/transition.
  Future<Map<String, dynamic>> _getJoined(String bookingId) async {
    final row = await _bookingRow(bookingId);
    if (row == null) {
      throw ApiError.server('Booking was created but could not be loaded.');
    }
    final list = await _joinRows([row]);
    return list.first;
  }

  /// Parses a booking date from the wire.
  ///
  /// The client may send either `YYYY-MM-DD` or a full ISO timestamp ending in
  /// `T23:59:59.000Z` (the last instant of that calendar day). Only the leading
  /// `YYYY-MM-DD` is meaningful here, because `bookings.start_date` /
  /// `end_date` are DATE columns. Reading the raw string instead of letting
  /// `DateTime.tryParse` apply a UTC->local shift kept shifting `endDate` one
  /// day forward, which both over-long bookings and false conflicts.
  DateTime _parseDate(Object? value, String field) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) throw ApiError.validation('$field is required.');
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (match == null) {
      throw ApiError.validation('$field must be a valid date (YYYY-MM-DD).');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    // Reject impossible calendar dates (e.g. 2026-02-30 rolls over to March).
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      throw ApiError.validation('$field must be a valid date (YYYY-MM-DD).');
    }
    return parsed;
  }

  double _d(Object? v) => (v as num).toDouble();

  /// Only UPI and COD exist. Anything else (including the removed Card /
  /// NetBanking options) is treated as UPI, so a stale client still works.
  static String _normalizePaymentMethod(String? raw) {
    final value = (raw ?? '').trim().toUpperCase();
    return PaymentMethod.all.contains(value) ? value : PaymentMethod.upi;
  }

  /// Lower-cased, validated UPI id or null. Shared with the payment service so
  /// a malformed stored value is never handed to a UPI app as a payee.
  static String? _cleanUpi(Object? raw) {
    final value = raw?.toString().trim().toLowerCase() ?? '';
    if (value.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9._-]{2,64}$')
        .hasMatch(value)) {
      return null;
    }
    return value;
  }
}
