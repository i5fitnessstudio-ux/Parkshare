/// Booking domain model with joined user / parking / vehicle / payment data.
library;

import 'parking_space.dart';

class BookingStatus {
  BookingStatus._();
  static const String requested = 'REQUESTED';
  static const String accepted = 'ACCEPTED';
  static const String rejected = 'REJECTED';
  static const String paymentPending = 'PAYMENT_PENDING';

  /// Cash on Delivery chosen but the cash has NOT been handed over yet. The
  /// owner must confirm receipt before the booking becomes [confirmed].
  static const String codPending = 'COD_PENDING';

  static const String confirmed = 'CONFIRMED';
  static const String active = 'ACTIVE';
  static const String completed = 'COMPLETED';
  static const String cancelled = 'CANCELLED';

  /// Statuses that occupy the parking (they block an overlapping booking).
  /// COD_PENDING is deliberately absent — unpaid cash must keep the slot
  /// bookable until the owner confirms.
  static const Set<String> occupying = {
    accepted,
    paymentPending,
    confirmed,
    active,
  };
}

/// The payment methods ParkShare supports.
///
/// * [cod] — cash handed to the owner.
/// * [upi] — the legacy direct owner-UPI deep link. Kept for persisted bookings
///   and the owner-side settle flow; hidden from the production payment screen.
/// * [razorpay] — the value stored on a booking/payment row for a Razorpay
///   Checkout payment.
/// * [online] — the client-only token the payment screen selects with; it is
///   never persisted.
///
/// Card and NetBanking are not separate methods: Razorpay Checkout hosts them.
class PaymentMethod {
  PaymentMethod._();
  static const String upi = 'UPI';
  static const String cod = 'COD';

  /// Client-side selection token for the Razorpay Checkout option.
  static const String online = 'ONLINE';

  /// Persisted/backend value for a Razorpay payment (`payments.payment_method`).
  static const String razorpay = 'RAZORPAY';

  /// Every value that may appear on a persisted booking / payment row. Includes
  /// [razorpay] so an online-paid booking still parses as a known method.
  static const Set<String> all = {upi, cod, razorpay};

  /// The methods the production payment screen offers. UPI is deliberately
  /// absent: the direct owner-UPI deep link is legacy and hidden.
  static const Set<String> selectable = {online, cod};

  static bool isValid(String? value) =>
      all.contains((value ?? '').trim().toUpperCase());
}

/// Payment lifecycle for a booking / payment record.
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

  /// The customer says they transferred via UPI, but the money has NOT been
  /// verified.
  ///
  /// SECURITY (audit C-01): this state exists precisely so that the app never
  /// has to claim a payment succeeded on the customer's word. It is produced by
  /// `POST /api/payments/upi/confirm`, which records only what the *client*
  /// asserted and leaves the booking unpaid. The owner — the party whose money
  /// is actually at stake — clears it through
  /// `PUT /api/payments/{bookingId}/upi/settle`, mirroring the COD flow, and
  /// only then does the status become [success].
  ///
  /// Deliberately NOT in [paid]: unverified funds must never be summed into
  /// owner earnings.
  static const String upiPendingVerification = 'UPI_PENDING_VERIFICATION';

  /// Money actually reached the owner. Only these are summed into the owner's
  /// Total Earnings; failed / cancelled / still-pending are excluded.
  static const Set<String> paid = {success, codConfirmed};

  /// States where the money has not (yet) arrived. Shared by the booking and
  /// the payment row so the UI can explain *why* it is not counted.
  static const Set<String> awaiting = {
    pending,
    codPending,
    upiPendingVerification,
  };

  /// True for a payment the customer claims to have made but that nobody has
  /// verified. Callers must treat it as "not paid" for every money calculation.
  static bool isUnverified(String? status) => status == upiPendingVerification;
}

class RentalType {
  RentalType._();
  static const String monthly = 'MONTHLY';
  static const String yearly = 'YEARLY';
}

/// Small nested payloads inside a booking.
///
/// A party involved in a booking is either the booked vehicle **user** or the
/// parking **owner**. The backend serialises the same `{id, name, phone}` shape
/// for both (joined through the relationship chain, never copied onto the
/// booking row), so one model covers both sides of the chain.
class BookingContact {
  final String id;
  final String name;

  /// Dialler-ready number, or null when the account has no usable phone.
  final String? phone;

  /// The contact's own UPI address, when the backend sends one (owners do;
  /// vehicle users may leave it blank).
  final String? upiId;

  const BookingContact({
    required this.id,
    required this.name,
    this.phone,
    this.upiId,
  });

  factory BookingContact.fromJson(Map<String, dynamic>? json) => BookingContact(
    id: json?['id']?.toString() ?? '',
    name: json?['name']?.toString() ?? '',
    phone: _cleanPhone(json?['phone']),
    upiId: _cleanUpi(json?['upiId']),
  );

  /// True when there is something to hand to the native dialler.
  bool get hasPhone => (phone ?? '').isNotEmpty;

  /// True when this contact can receive a UPI payment.
  bool get hasUpiId => upiId != null;

  /// The best available label, used for the chat header.
  String get displayName => name.trim().isEmpty ? '' : name.trim();
}

/// The booked vehicle user. Alias of [BookingContact] (same payload shape).
typedef BookingUser = BookingContact;

/// Drops empty values and anything that cannot be dialled, so a missing or
/// malformed number becomes `null` and the UI can say "unavailable".
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

/// Trims a value to a non-empty string, or null when there is nothing useful.
String? _cleanText(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

/// Normalises a UPI virtual payment address, or null when absent/malformed so
/// the UI can say "not configured yet" instead of showing an empty box.
String? _cleanUpi(Object? raw) {
  final value = raw?.toString().trim().toLowerCase() ?? '';
  if (value.isEmpty) return null;
  if (!RegExp(r'^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9._-]{2,64}$').hasMatch(value)) {
    return null;
  }
  return value;
}

class BookingParking {
  final String id;
  final String name;
  final String address;
  final List<String> photoUrls;
  const BookingParking({
    required this.id,
    required this.name,
    required this.address,
    this.photoUrls = const [],
  });

  String? get thumbnailUrl => photoUrls.isNotEmpty ? photoUrls.first : null;

  factory BookingParking.fromJson(Map<String, dynamic>? json) {
    final urls = json?['photoUrls'] is List
        ? (json!['photoUrls'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    return BookingParking(
      id: json?['id']?.toString() ?? '',
      name: json?['name']?.toString() ?? '',
      address: json?['address']?.toString() ?? '',
      photoUrls: urls,
    );
  }
}

class BookingVehicle {
  final String id;
  final String type;
  final String brand;
  final String model;
  final String registrationNumber;
  final String? photoUrl;
  const BookingVehicle({
    required this.id,
    required this.type,
    required this.brand,
    required this.model,
    required this.registrationNumber,
    this.photoUrl,
  });

  factory BookingVehicle.fromJson(Map<String, dynamic>? json) => BookingVehicle(
    id: json?['id']?.toString() ?? '',
    type: json?['type']?.toString() ?? '',
    brand: json?['brand']?.toString() ?? '',
    model: json?['model']?.toString() ?? '',
    registrationNumber: json?['registrationNumber']?.toString() ?? '',
    photoUrl: json?['photoUrl']?.toString(),
  );
}

class BookingPayment {
  final String? id;
  final double? amount;
  final String paymentMethod;
  final String transactionId;
  final String paymentStatus;
  final DateTime? paidAt;

  /// The owner's UPI address this payment was made to.
  final String? upiId;

  /// Razorpay payment id when paid online.
  final String? razorpayPaymentId;

  /// Human-readable booking reference (e.g. `PSK-4F2A9C31`) shown in the UPI
  /// app and on the receipt.
  final String? reference;

  const BookingPayment({
    this.id,
    this.amount,
    this.paymentMethod = '',
    this.transactionId = '',
    this.paymentStatus = '',
    this.paidAt,
    this.upiId,
    this.razorpayPaymentId,
    this.reference,
  });

  factory BookingPayment.fromJson(Map<String, dynamic>? json) {
    double? d(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return BookingPayment(
      id: json?['id']?.toString(),
      amount: d(json?['amount']),
      paymentMethod: json?['paymentMethod']?.toString() ?? '',
      transactionId: json?['transactionId']?.toString() ?? '',
      paymentStatus: json?['paymentStatus']?.toString() ?? '',
      paidAt: DateTime.tryParse(json?['paidAt']?.toString() ?? ''),
      upiId: _cleanUpi(json?['upiId']),
      razorpayPaymentId: _cleanText(json?['razorpayPaymentId']),
      reference: (json?['reference']?.toString() ?? '').trim().isEmpty
          ? null
          : json!['reference'].toString().trim(),
    );
  }

  /// True when the owner has actually received the money.
  bool get isPaid => PaymentStatus.paid.contains(paymentStatus);

  /// Cash chosen but not yet handed over.
  bool get isCodPending => paymentStatus == PaymentStatus.codPending;

  /// The customer claims a UPI transfer that no owner has verified yet.
  bool get isUpiUnverified => PaymentStatus.isUnverified(paymentStatus);
}

class Booking {
  final String bookingId;
  final String parkingId;
  final String userId;
  final String ownerId;
  final String vehicleId;
  final String rentalType; // MONTHLY | YEARLY
  final DateTime startDate;
  final DateTime endDate;
  final double amount;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final BookingUser user;

  /// The single physical slot this booking holds. Null on bookings created
  /// before slot allocation existed.
  final ParkingSpace? parkingSpace;

  /// Convenience mirror of the slot code, so a card can print "C1" without
  /// digging into [parkingSpace].
  final String? spaceCode;

  /// The parking owner, resolved server-side through
  /// booking -> parking_listings -> users (user side needs name + phone).
  final BookingContact owner;
  final BookingParking parking;
  final BookingVehicle vehicle;
  final BookingPayment payment;

  /// Apartment / parking identification. The backend mirrors the parking name
  /// here so the chat header needs no extra lookup.
  final String apartmentName;

  // ---- Payment (UPI / Cash on Delivery) -------------------------------

  /// UPI or COD. Mirrors the latest `payments` row.
  final String paymentMethod;

  /// PENDING / SUCCESS / FAILED / COD_PENDING / COD_CONFIRMED.
  final String paymentStatus;

  /// The owner's UPI id captured when the booking was created — the exact
  /// address this booking was paid (or will be paid) to.
  final String? ownerUpiIdSnapshot;

  /// Human-readable booking reference, e.g. `PSK-4F2A9C31`.
  final String? paymentReference;

  /// Razorpay payment id (gateway) when paid online. Separate from
  /// [paymentReference] (booking/receipt reference).
  final String? razorpayPaymentId;

  /// Gateway transaction id (UPI/COD settlement reference) or the owner's
  /// confirmation id.
  final String? upiTransactionId;

  /// When the owner marked a COD payment as received.
  final DateTime? codConfirmedAt;

  /// When the owner verified a UPI payment (`upi/settle`). Null while the
  /// payment is still awaiting verification (audit C-01).
  final DateTime? upiVerifiedAt;

  const Booking({
    required this.bookingId,
    required this.parkingId,
    required this.userId,
    required this.ownerId,
    required this.vehicleId,
    required this.rentalType,
    required this.startDate,
    required this.endDate,
    required this.amount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.user,
    required this.owner,
    required this.parking,
    required this.vehicle,
    required this.payment,
    this.apartmentName = '',
    this.parkingSpace,
    this.spaceCode,
    this.paymentMethod = PaymentMethod.upi,
    this.paymentStatus = PaymentStatus.pending,
    this.ownerUpiIdSnapshot,
    this.paymentReference,
    this.razorpayPaymentId,
    this.upiTransactionId,
    this.codConfirmedAt,
    this.upiVerifiedAt,
  });

  bool get isUserSide => true;

  bool get requiresOwnerAction => status == BookingStatus.requested;

  bool get canPay =>
      status == BookingStatus.accepted ||
      status == BookingStatus.paymentPending;

  bool get isActiveOrUpcoming =>
      status == BookingStatus.confirmed || status == BookingStatus.active;

  // ---- Payment helpers ------------------------------------------------

  /// Cash on Delivery selected, cash not yet handed over.
  bool get isCodPending => status == BookingStatus.codPending;

  bool get isCod => paymentMethod == PaymentMethod.cod;

  /// The owner actually received the money (UPI success or confirmed COD).
  bool get isPaymentComplete => PaymentStatus.paid.contains(paymentStatus);

  /// UPI claimed by the customer but not yet verified by the owner.
  ///
  /// SECURITY (audit C-01): [isPaymentComplete] is false here on purpose, and
  /// this getter exists so the UI can *say* why instead of pretending the
  /// booking is unpaid.
  bool get isUpiPendingVerification =>
      PaymentStatus.isUnverified(paymentStatus);

  /// True only for the LEGACY direct owner-UPI flow: the payment method is
  /// actually UPI *and* the customer has declared a transfer nobody verified.
  ///
  /// The owner-side "Verify UPI Payment" action and the owner's UPI id row must
  /// be gated on this, never on [isUpiPendingVerification] alone. A Razorpay
  /// booking is verified by the gateway HMAC and must never show a manual "verify
  /// the money arrived" affordance, nor expose the owner's personal UPI id.
  bool get isLegacyDirectUpi =>
      paymentMethod == PaymentMethod.upi && isUpiPendingVerification;

  /// True for an online (Razorpay) booking, whatever its current status.
  bool get isRazorpay => paymentMethod == PaymentMethod.razorpay;

  /// True when the owner's own UPI address may be shown to the owner for THIS
  /// booking. Payment-method-scoped so a Razorpay booking can never surface the
  /// owner's personal UPI id.
  bool get showsOwnerUpiId =>
      paymentMethod == PaymentMethod.upi && ownerUpiIdUsed?.isNotEmpty == true;

  /// The UPI address this booking pays: the snapshot taken when the booking
  /// was made, falling back to the owner's live id.
  String? get ownerUpiIdUsed => ownerUpiIdSnapshot ?? owner.upiId;

  /// The owner's live UPI id (may be null if never configured).
  String? get ownerUpiId => owner.upiId;

  // ---- Contact shortcuts (used by the Call buttons and the chat header) ----

  String get ownerName => owner.displayName;
  String? get ownerPhone => owner.hasPhone ? owner.phone : null;
  String get userName => user.displayName;
  String? get userPhone => user.hasPhone ? user.phone : null;

  /// Apartment / parking identification. The backend mirrors the parking name
  /// here so the chat header needs no extra lookup.
  String get apartmentLabel =>
      apartmentName.isNotEmpty ? apartmentName : parking.name;

  factory Booking.fromJson(Map<String, dynamic> json) {
    DateTime? dt(Object? v) => DateTime.tryParse(v?.toString() ?? '');
    return Booking(
      bookingId: json['bookingId']?.toString() ?? '',
      parkingId: json['parkingId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      vehicleId: json['vehicleId']?.toString() ?? '',
      rentalType: json['rentalType']?.toString() ?? RentalType.monthly,
      startDate: dt(json['startDate']) ?? DateTime.now(),
      endDate: dt(json['endDate']) ?? DateTime.now(),
      amount: (json['amount'] is num)
          ? (json['amount'] as num).toDouble()
          : double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      status: json['status']?.toString() ?? BookingStatus.requested,
      createdAt: dt(json['createdAt']) ?? DateTime.now(),
      updatedAt: dt(json['updatedAt']) ?? DateTime.now(),
      user: _contact(
        json,
        nestedKey: 'user',
        nameKey: 'userName',
        phoneKey: 'userPhone',
        fallbackId: json['userId']?.toString(),
      ),
      owner: _contact(
        json,
        nestedKey: 'owner',
        nameKey: 'ownerName',
        phoneKey: 'ownerPhone',
        upiKey: 'ownerUpiId',
        fallbackId: json['ownerId']?.toString(),
      ),
      parking: BookingParking.fromJson(
        json['parking'] as Map<String, dynamic>?,
      ),
      vehicle: BookingVehicle.fromJson(
        json['vehicle'] as Map<String, dynamic>?,
      ),
      payment: BookingPayment.fromJson(
        json['payment'] as Map<String, dynamic>?,
      ),
      apartmentName: (json['apartmentName']?.toString() ?? '').trim(),
      parkingSpace: json['parkingSpace'] is Map<String, dynamic>
          ? ParkingSpace.fromJson(json['parkingSpace'] as Map<String, dynamic>)
          : null,
      spaceCode: (json['spaceCode']?.toString() ?? '').trim().isEmpty
          ? null
          : json['spaceCode'].toString(),
      paymentMethod: PaymentMethod.isValid(json['paymentMethod']?.toString())
          ? json['paymentMethod'].toString().trim().toUpperCase()
          : PaymentMethod.upi,
      // The booking row mirrors the payment; fall back to the nested payment
      // object so either payload shape works.
      paymentStatus:
          _cleanText(json['paymentStatus']) ??
          _cleanText((json['payment'] as Map?)?['paymentStatus']) ??
          PaymentStatus.pending,
      ownerUpiIdSnapshot: _cleanUpi(json['ownerUpiIdSnapshot']),
      paymentReference:
          (json['paymentReference']?.toString() ?? '').trim().isEmpty
          ? null
          : json['paymentReference'].toString().trim(),
      razorpayPaymentId: ((json['razorpayPaymentId']?.toString() ?? (json['payment'] is Map ? ((json['payment'] as Map)['razorpayPaymentId']?.toString() ?? '') : '')).trim().isEmpty)
          ? null
          : (json['razorpayPaymentId']?.toString() ?? (json['payment'] is Map ? ((json['payment'] as Map)['razorpayPaymentId']?.toString() ?? '') : '')).trim(),
      upiTransactionId:
          (json['upiTransactionId']?.toString() ?? '').trim().isEmpty
          ? null
          : json['upiTransactionId'].toString().trim(),
      codConfirmedAt: dt(json['codConfirmedAt']),
      upiVerifiedAt: dt(json['upiVerifiedAt']),
    );
  }

  /// "Car Space 1 (C1)" when the owner named the slot, else just "C1".
  String get spaceLabel {
    final code = spaceCode;
    if (code == null || code.isEmpty) return '';
    final name = parkingSpace?.spaceName?.trim() ?? '';
    if (name.isEmpty || name == code) return code;
    return '$name ($code)';
  }

  /// Reads a party from the nested object the backend sends, falling back to
  /// the flat mirror so either payload shape works.
  static BookingContact _contact(
    Map<String, dynamic> json, {
    required String nestedKey,
    required String nameKey,
    required String phoneKey,
    String upiKey = '',
    String? fallbackId,
  }) {
    final nested = json[nestedKey];
    final contact = BookingContact.fromJson(
      nested is Map<String, dynamic> ? nested : null,
    );
    final name = contact.name.isNotEmpty
        ? contact.name
        : (json[nameKey]?.toString() ?? '').trim();
    final phone = contact.hasPhone
        ? contact.phone
        : _cleanPhone(json[phoneKey]);
    final upi =
        contact.upiId ?? (upiKey.isEmpty ? null : _cleanUpi(json[upiKey]));
    final id = contact.id.isNotEmpty ? contact.id : (fallbackId ?? '');
    if (id.isEmpty && name.isEmpty && phone == null && upi == null) {
      return const BookingContact(id: '', name: '');
    }
    return BookingContact(id: id, name: name, phone: phone, upiId: upi);
  }
}
