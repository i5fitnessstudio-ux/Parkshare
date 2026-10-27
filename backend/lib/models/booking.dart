/// Booking domain constants + row -> JSON mapping (backend).
library;

import 'parking_space.dart';

class BookingStatus {
  BookingStatus._();
  static const String requested = 'REQUESTED';
  static const String accepted = 'ACCEPTED';
  static const String rejected = 'REJECTED';
  static const String paymentPending = 'PAYMENT_PENDING';

  /// Cash on Delivery chosen but the cash has NOT been handed over yet.
  /// The owner must tap "Mark COD Received" before this becomes
  /// [confirmed]. It is deliberately NOT in [occupying] / occupyingStatusList
  /// so a pending COD booking keeps showing the slot as available.
  static const String codPending = 'COD_PENDING';

  static const String confirmed = 'CONFIRMED';
  static const String active = 'ACTIVE';
  static const String completed = 'COMPLETED';
  static const String cancelled = 'CANCELLED';

  /// Statuses that occupy the parking (blocking overlapping bookings).
  static const Set<String> occupying = {
    accepted,
    paymentPending,
    confirmed,
    active,
  };
}

/// The canonical "this status reserves capacity" list.
///
/// Audit (PART 20): REQUESTED does NOT reserve a slot on purpose — the existing
/// product rule lets several users request the same parking and the owner
/// accepts one. COD_PENDING does NOT reserve a slot either: the vehicle user
/// has chosen cash but has not paid yet, so the space must stay bookable
/// until the owner confirms the cash. REJECTED / CANCELLED / COMPLETED
/// release the slot, so only ACCEPTED, PAYMENT_PENDING, CONFIRMED and ACTIVE
/// block it.
const List<String> occupyingStatusList = [
  BookingStatus.accepted,
  BookingStatus.paymentPending,
  BookingStatus.confirmed,
  BookingStatus.active,
];

class RentalType {
  RentalType._();
  static const String monthly = 'MONTHLY';
  static const String yearly = 'YEARLY';
  static const Set<String> all = {monthly, yearly};
}

/// The only two payment methods ParkShare supports. Card and NetBanking were
/// removed on purpose: money always goes to the parking owner's own UPI id,
/// or is handed over in cash.
class PaymentMethod {
  PaymentMethod._();
  static const String upi = 'UPI';
  static const String cod = 'COD';
  static const Set<String> all = {upi, cod};
}

class PaymentStatus {
  PaymentStatus._();
  static const String pending = 'PENDING';
  static const String success = 'SUCCESS';
  static const String failed = 'FAILED';
  static const String refunded = 'REFUNDED';

  /// COD chosen, cash not yet received.
  static const String codPending = 'COD_PENDING';

  /// Owner confirmed the cash was received — counts towards earnings.
  static const String codConfirmed = 'COD_CONFIRMED';

  /// SECURITY (audit C-01): the user says the UPI app reported success, but
  /// the backend has NO verifiable evidence of settlement. A bare `upi://`
  /// intent is a one-way, unsigned hand-off — the app cannot tell the server
  /// that money moved, so the server must not treat it as paid.
  ///
  /// This state therefore means **"claimed by the payer, not verified"**:
  ///  * it is NOT in [paid], so it never counts as owner earnings;
  ///  * it does NOT occupy the booking slot, exactly like [codPending];
  ///  * it can only become [success] through owner settlement
  ///    (`PUT /api/payments/{bookingId}/upi/settle`), or automatically once a
  ///    real PSP webhook is integrated.
  ///
  /// It exists so the product can still show "payment submitted" honestly
  /// instead of fabricating a SUCCESS and a made-up transaction id.
  static const String upiPendingVerification = 'UPI_PENDING_VERIFICATION';

  /// Statuses where the owner has actually been paid and the amount must
  /// appear in the dashboard's Total Earnings.
  ///
  /// Only a server-verifiable outcome may be here: an owner-confirmed cash
  /// handover, or a UPI payment the owner settled after seeing the money in
  /// their account. A client *assertion* is never enough.
  static const Set<String> paid = {success, codConfirmed};

  /// Statuses that are still waiting on money.
  static const Set<String> awaiting = {
    pending,
    codPending,
    upiPendingVerification,
  };

  /// True when the money has NOT been verified yet, so neither the slot nor
  /// the owner's earnings may move.
  static bool isUnverified(String value) =>
      awaiting.contains(value.toUpperCase());
}

String _dateStr(DateTime d) => d.toIso8601String().substring(0, 10);

/// Normalises a stored phone number for the dialler: keeps digits and a
/// leading `+`, drops spaces/dashes/brackets. Returns null when nothing
/// dialable is left, so the client can say "phone number is unavailable".
String? _cleanPhone(Object? raw) {
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

String? _cleanText(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

/// Normalises a UPI id for the wire: lower-cased, or null when absent/malformed
/// so the client can render "no UPI ID configured yet" instead of an empty box.
String? _cleanUpi(Object? raw) {
  final value = _cleanText(raw)?.toLowerCase();
  if (value == null) return null;
  if (!RegExp(r'^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9._-]{2,64}$').hasMatch(value)) {
    return null;
  }
  return value;
}

/// Booking row -> compact JSON (booking-level fields only).
Map<String, dynamic> bookingCoreJson(Map<String, dynamic> row) {
  final spaceId = row['parking_space_id']?.toString();
  final status = row['status']?.toString() ?? BookingStatus.requested;
  return {
    'bookingId': row['id']?.toString() ?? '',
    'parkingId': row['parking_id']?.toString() ?? '',
    // The specific physical slot this booking holds. Null on legacy bookings
    // created before slot allocation existed, and on a COD_PENDING booking —
    // pending cash must not hold the slot, so it gets one on confirmation.
    'parkingSpaceId': (spaceId == null || spaceId.isEmpty) ? null : spaceId,
    'userId': row['user_id']?.toString() ?? '',
    'ownerId': row['owner_id']?.toString() ?? '',
    'vehicleId': row['vehicle_id']?.toString() ?? '',
    'rentalType': row['rental_type']?.toString() ?? '',
    'startDate': (row['start_date'] as DateTime?)?.let(_dateStr) ?? '',
    'endDate': (row['end_date'] as DateTime?)?.let(_dateStr) ?? '',
    'amount': double.tryParse(row['amount']?.toString() ?? ''),
    'status': status,
    // Mirror so a client can read the booking status under the explicit name
    // without a second source of truth (same column, same value).
    'bookingStatus': status,
    // ---- Payment (mirrors the latest `payments` row) ----
    'paymentMethod':
        row['payment_method']?.toString() ?? PaymentMethod.upi,
    'paymentStatus':
        row['payment_status']?.toString() ?? PaymentStatus.pending,
    // Owner UPI id captured when the booking was made: the exact address the
    // user paid (or will pay) the owner.
    'ownerUpiIdSnapshot': _cleanUpi(row['owner_upi_id_snapshot']),
    'paymentReference': _cleanText(row['payment_reference']),
    // Gateway transaction id (e.g. Razorpay payment id) is shown separately
    // from the booking/receipt reference. Never fall back to paymentReference.
    'razorpayPaymentId': _cleanText(row['razorpay_payment_id']),
    'upiTransactionId': _cleanText(row['upi_transaction_id']),
    'codConfirmedAt': (row['cod_confirmed_at'] as DateTime?)
        ?.toIso8601String(),
    'codConfirmedBy': row['cod_confirmed_by']?.toString(),
    // SECURITY (audit C-01): when the parking owner settled a UPI payment that
    // the payer had only *claimed*. Until this is set, the payment is
    // UPI_PENDING_VERIFICATION and must not be treated as paid.
    'upiVerifiedAt': (row['upi_verified_at'] as DateTime?)?.toIso8601String(),
    'upiVerifiedBy': row['upi_verified_by']?.toString(),
    'createdAt': (row['created_at'] as DateTime?)?.toIso8601String() ?? '',
    'updatedAt': (row['updated_at'] as DateTime?)?.toIso8601String() ?? '',
  };
}

/// Joined booking payload for owner/user booking lists and detail.
/// Returns everything Flutter needs for one booking card in a single call.
///
/// Contact details are resolved through the existing relationships
/// (booking -> user / parking -> owner) and never stored on the booking row:
///   * `user`  — the booked vehicle user  (owner side needs name + phone)
///   * `owner` — the parking owner        (user side needs name + phone)
/// No password / token / OTP / auth material is ever serialised here.
Map<String, dynamic> bookingJoinedJson({
  required Map<String, dynamic> bookingRow,
  required Map<String, dynamic>? userRow,
  required Map<String, dynamic>? parkingRow,
  required Map<String, dynamic>? vehicleRow,
  Map<String, dynamic>? ownerRow,
  Map<String, dynamic>? paymentRow,
  Map<String, dynamic>? parkingSpaceRow,
  List<String> photoUrls = const [],
}) {
  final core = bookingCoreJson(bookingRow);

  final userName = userRow?['name']?.toString() ?? '';
  final userPhone = _cleanPhone(userRow?['phone']);
  core['user'] = userRow == null
      ? null
      : {
          'id': userRow['id']?.toString() ?? '',
          'name': userName,
          'phone': userPhone,
        };
  // Flat mirror of the booked user so either shape can be consumed.
  core['userName'] = userName;
  core['userPhone'] = userPhone;

  final ownerName = ownerRow?['name']?.toString() ?? '';
  final ownerPhone = _cleanPhone(ownerRow?['phone']);
  // The owner's LIVE UPI id (from `users.upi_id`). The SNAPSHOT taken at
  // booking time is what the user actually paid, and it lives on the booking
  // row; this live value is what the payment screen offers for a new booking.
  final ownerUpi = _cleanUpi(ownerRow?['upi_id']);
  core['owner'] = ownerRow == null
      ? null
      : {
          'id': ownerRow['id']?.toString() ?? '',
          'name': ownerName,
          'phone': ownerPhone,
          'upiId': ownerUpi,
          'hasUpiId': ownerUpi != null,
        };
  // Flat mirror of the parking owner (user side needs id/name/phone/upi).
  core['ownerName'] = ownerName;
  core['ownerPhone'] = ownerPhone;
  core['ownerUpiId'] = ownerUpi;
  // The address this booking is actually being paid to: the snapshot taken at
  // booking time, falling back to the owner's live id.
  core['ownerUpiIdUsed'] = core['ownerUpiIdSnapshot'] ?? ownerUpi;

  final parkingName = parkingRow?['parking_name']?.toString() ?? '';
  core['parking'] = parkingRow == null
      ? null
      : {
          'id': parkingRow['id']?.toString() ?? '',
          'name': parkingName,
          'address': parkingRow['address']?.toString() ?? '',
          'photoUrls': photoUrls,
          'thumbnailUrl': photoUrls.isNotEmpty ? photoUrls.first : null,
        };
  // "Apartment / parking" identification used by the chat header.
  core['apartmentName'] = parkingName;
  // The allocated slot (code + dimensions) so both sides can see exactly
  // which physical space was reserved. Null on legacy bookings.
  core['parkingSpace'] = parkingSpaceRow == null
      ? null
      : parkingSpaceRowToJson(parkingSpaceRow);
  core['spaceCode'] =
      parkingSpaceRow?['space_code']?.toString() ??
      core['parkingSpaceId']?.toString();
  core['vehicle'] = vehicleRow == null
      ? null
      : {
          'id': vehicleRow['id']?.toString() ?? '',
          'type': vehicleRow['vehicle_type']?.toString() ?? '',
          'brand': vehicleRow['brand']?.toString() ?? '',
          'model': vehicleRow['model']?.toString() ?? '',
          'registrationNumber':
              vehicleRow['registration_number']?.toString() ?? '',
          'photoUrl': vehicleRow['photo_url']?.toString(),
        };
  core['payment'] = paymentRow == null
      ? null
      : {
          'id': paymentRow['id']?.toString() ?? '',
          'amount': double.tryParse(paymentRow['amount']?.toString() ?? ''),
          'paymentMethod': paymentRow['payment_method']?.toString() ?? '',
          'transactionId': paymentRow['transaction_id']?.toString() ?? '',
          'paymentStatus': paymentRow['payment_status']?.toString() ?? '',
          // Razorpay's own payment id, kept separate from the booking
          // reference/receipt so the receipt can show both honestly.
          'razorpayPaymentId':
              _cleanText(paymentRow['razorpay_payment_id']),
          'razorpayOrderId': _cleanText(paymentRow['razorpay_order_id']),
          // The owner's UPI address this payment was made to.
          'upiId': _cleanUpi(paymentRow['upi_id']),
          'reference': _cleanText(paymentRow['reference']),
          'paidAt': (paymentRow['paid_at'] as DateTime?)?.toIso8601String(),
          'createdAt': (paymentRow['created_at'] as DateTime?)
              ?.toIso8601String(),
        };
  return core;
}

/// Extension helper so the `_dateStr` util above reads cleanly.
extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
