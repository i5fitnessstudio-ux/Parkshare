import 'booking.dart';

/// Payment details of the OWNER of one selected parking listing.
///
/// Returned by `GET /api/payments/parking/{parkingId}/owner` so the payment
/// screen can show (and pay) that owner's own UPI id — never a global one.
///
/// [hasUpiId] drives the UI: when the owner has not configured a UPI id the
/// screen must show "This parking owner has not configured a UPI ID yet…" and
/// push the user towards Cash on Delivery.
class OwnerPaymentInfo {
  final String parkingId;
  final String parkingName;
  final String address;
  final String? city;
  final String ownerId;
  final String ownerName;

  /// Dialler-ready number, or null when the owner has no usable phone.
  final String? ownerPhone;

  /// The owner's own UPI virtual payment address (normalised), or null.
  final String? ownerUpiId;

  final bool hasUpiId;
  final List<String> paymentMethods;
  final bool upiAvailable;
  final bool codAvailable;

  const OwnerPaymentInfo({
    required this.parkingId,
    required this.parkingName,
    required this.address,
    required this.ownerId,
    required this.ownerName,
    this.city,
    this.ownerPhone,
    this.ownerUpiId,
    this.hasUpiId = false,
    this.paymentMethods = const [PaymentMethod.upi, PaymentMethod.cod],
    this.upiAvailable = false,
    this.codAvailable = true,
  });

  /// Only UPI and COD are ever offered. Derived from [paymentMethods] but
  /// intersected with the supported set, so an unexpected server value can
  /// never surface a Card / NetBanking option.
  List<String> get availableMethods => paymentMethods
      .where((m) => PaymentMethod.all.contains(m.toUpperCase()))
      .map((m) => m.toUpperCase())
      .toSet()
      .toList();

  factory OwnerPaymentInfo.fromJson(Map<String, dynamic> json) {
    final upi = (json['ownerUpiId']?.toString() ?? '').trim().toLowerCase();
    final hasUpi = upi.isNotEmpty;
    return OwnerPaymentInfo(
      parkingId: json['parkingId']?.toString() ?? '',
      parkingName: json['parkingName']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      city: (json['city']?.toString() ?? '').trim().isEmpty
          ? null
          : json['city'].toString(),
      ownerId: json['ownerId']?.toString() ?? '',
      ownerName: json['ownerName']?.toString() ?? '',
      ownerPhone: (json['ownerPhone']?.toString() ?? '').trim().isEmpty
          ? null
          : json['ownerPhone'].toString().trim(),
      ownerUpiId: hasUpi ? upi : null,
      hasUpiId: json['hasUpiId'] == true || hasUpi,
      paymentMethods: json['paymentMethods'] is List
          ? (json['paymentMethods'] as List).map((e) => e.toString()).toList()
          : const [PaymentMethod.upi, PaymentMethod.cod],
      upiAvailable: json['upiAvailable'] == true || hasUpi,
      codAvailable: json['codAvailable'] != false,
    );
  }
}

/// Owner contact block shown to the user on the COD screen
/// ("Please contact your parking owner").
class OwnerContact {
  final String name;
  final String? phone;

  /// Optional: shown when the owner also accepts UPI.
  final String? upiId;

  final String parkingName;
  final String address;

  const OwnerContact({
    required this.name,
    required this.parkingName,
    required this.address,
    this.phone,
    this.upiId,
  });

  factory OwnerContact.fromJson(Map<String, dynamic>? json) => OwnerContact(
    name: json?['name']?.toString() ?? '',
    phone: (json?['phone']?.toString() ?? '').trim().isEmpty
        ? null
        : json!['phone'].toString().trim(),
    upiId: (json?['upiId']?.toString() ?? '').trim().isEmpty
        ? null
        : json!['upiId'].toString().trim().toLowerCase(),
    parkingName: json?['parkingName']?.toString() ?? '',
    address: json?['address']?.toString() ?? '',
  );

  bool get hasPhone => (phone ?? '').isNotEmpty;
  bool get hasUpiId => (upiId ?? '').isNotEmpty;
}

/// Owner settlement totals, **computed by the backend**.
///
/// AUDIT C-02: the owner dashboard used to derive "Total Earnings" by summing
/// `bookings.amount` for every locally-loaded booking whose status was in the
/// paid set. That is a money figure, client-side, dependent on which page of
/// bookings happened to be cached, and checked by nobody but the owner's own
/// phone. This model carries the server's aggregate instead; the dashboard
/// falls back to the local derivation only if this call fails, and says so.
class OwnerEarningsSummary {
  final String ownerId;

  /// Money the owner has actually received: SUCCESS + COD_CONFIRMED only.
  /// A `UPI_PENDING_VERIFICATION` booking is excluded server-side.
  final double totalEarnings;

  final int paidBookings;

  /// COD chosen, cash not yet handed over — worth nothing yet.
  final int codPending;

  /// UPI claimed by the customer, not yet verified by the owner. Surfaced so
  /// the owner can go and settle it.
  final int upiAwaitingVerification;

  final int pendingRequests;
  final int activeBookings;
  final int completedBookings;
  final int totalBookings;

  /// Online (Razorpay) owner share awaiting settlement, in integer paise.
  ///
  /// This is the marketplace ledger (`payment_transfers`). COD is deliberately
  /// excluded: that cash is already in the owner's hand, so it is not "pending
  /// settlement". Payment PAID does NOT imply settlement complete.
  final int pendingSettlementPaise;

  /// Owner share already paid out and recorded as settled, in integer paise.
  /// This remains 0 while Razorpay Route is disabled; once an administrator
  /// records a real manual bank/UPI payout it reflects that settlement.
  final int settledPaise;

  /// Number of settlement-ledger entries (Razorpay earnings) for this owner.
  final int transferCount;

  /// Newest-first, owner-scoped settlement entries for the Payments screen.
  final List<OwnerSettlementEntry> settlementEntries;

  /// `'server'` — recorded so the UI can label the figure's provenance.
  final String source;

  const OwnerEarningsSummary({
    required this.ownerId,
    required this.totalEarnings,
    this.paidBookings = 0,
    this.codPending = 0,
    this.upiAwaitingVerification = 0,
    this.pendingRequests = 0,
    this.activeBookings = 0,
    this.completedBookings = 0,
    this.totalBookings = 0,
    this.pendingSettlementPaise = 0,
    this.settledPaise = 0,
    this.transferCount = 0,
    this.settlementEntries = const [],
    this.source = 'server',
  });

  /// Bookings waiting on the owner to confirm money, either way.
  int get awaitingOwnerVerification => codPending + upiAwaitingVerification;

  /// True when the figure came from the server rather than a client sum.
  bool get isAuthoritative => source == 'server';

  factory OwnerEarningsSummary.fromJson(Map<String, dynamic> json) {
    double d(Object? v) =>
        v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    int i(Object? v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    final entries = json['settlementEntries'];
    return OwnerEarningsSummary(
      ownerId: json['ownerId']?.toString() ?? '',
      totalEarnings: d(json['totalEarnings']),
      paidBookings: i(json['paidBookings']),
      codPending: i(json['codPending']),
      upiAwaitingVerification: i(json['upiAwaitingVerification']),
      pendingRequests: i(json['pendingRequests']),
      activeBookings: i(json['activeBookings']),
      completedBookings: i(json['completedBookings']),
      totalBookings: i(json['totalBookings']),
      pendingSettlementPaise: i(json['pendingSettlementPaise']),
      settledPaise: i(json['settledPaise']),
      transferCount: i(json['transferCount']),
      settlementEntries: entries is List
          ? entries
                .whereType<Map>()
                .map(
                  (e) =>
                      OwnerSettlementEntry.fromJson(e.cast<String, dynamic>()),
                )
                .toList()
          : const [],
      source: json['source']?.toString() ?? 'server',
    );
  }
}

/// One owner settlement-ledger line (a Razorpay booking's owner share).
///
/// Values are integer paise. `settlementStatus` is independent of the payment
/// status: a booking can be `PAID` while its settlement is still `PENDING`.
class OwnerSettlementEntry {
  final String? bookingId;
  final String parkingName;
  final int grossAmountPaise;
  final int platformFeePaise;
  final int ownerAmountPaise;
  final String currency;
  final String settlementStatus;
  final String transferStatus;
  final String paymentStatus;
  final String? razorpayPaymentId;
  final DateTime? createdAt;

  const OwnerSettlementEntry({
    required this.bookingId,
    required this.parkingName,
    required this.grossAmountPaise,
    required this.platformFeePaise,
    required this.ownerAmountPaise,
    this.currency = 'INR',
    this.settlementStatus = 'PENDING',
    this.transferStatus = 'PENDING',
    this.paymentStatus = '',
    this.razorpayPaymentId,
    this.createdAt,
  });

  bool get isSettled => settlementStatus.toUpperCase() == 'SETTLED';

  factory OwnerSettlementEntry.fromJson(Map<String, dynamic> json) {
    int i(Object? v) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
    final rawDate = json['createdAt']?.toString();
    return OwnerSettlementEntry(
      bookingId: (json['bookingId']?.toString() ?? '').trim().isEmpty
          ? null
          : json['bookingId'].toString(),
      parkingName: json['parkingName']?.toString() ?? '',
      grossAmountPaise: i(json['grossAmountPaise']),
      platformFeePaise: i(json['platformFeePaise']),
      ownerAmountPaise: i(json['ownerAmountPaise']),
      currency: json['currency']?.toString() ?? 'INR',
      settlementStatus: json['settlementStatus']?.toString() ?? 'PENDING',
      transferStatus: json['transferStatus']?.toString() ?? 'PENDING',
      paymentStatus: json['paymentStatus']?.toString() ?? '',
      razorpayPaymentId:
          (json['razorpayPaymentId']?.toString() ?? '').trim().isEmpty
          ? null
          : json['razorpayPaymentId'].toString(),
      createdAt: rawDate == null ? null : DateTime.tryParse(rawDate),
    );
  }
}

/// Owner payment / settlement account status, as returned by
/// `GET /api/payments/owner/payment-account`.
///
/// This model is intentionally masked: it only ever carries [bankLast4] and
/// never a full account number, IFSC, PAN/KYC, linked-account id or provider
/// secret. Those values are private to the owner↔backend boundary and are not
/// returned to the app after setup.
class OwnerPaymentAccount {
  final String ownerId;
  final String provider;

  /// NOT_STARTED / PENDING / VERIFIED / ACTION_REQUIRED / REJECTED.
  final String onboardingStatus;

  /// Whether ParkShare can pay this owner out through the provider. Stays
  /// false until Razorpay Route onboarding actually completes.
  final bool settlementEnabled;

  /// True once the owner has saved any setup (even if the provider has not yet
  /// verified it).
  final bool setupCompleted;

  final String accountHolderName;
  final String legalName;
  final String accountType;

  /// Last four digits only, e.g. "4582".
  final String bankLast4;
  final DateTime? consentAcceptedAt;
  final DateTime? updatedAt;

  const OwnerPaymentAccount({
    required this.ownerId,
    this.provider = 'RAZORPAY',
    this.onboardingStatus = 'NOT_STARTED',
    this.settlementEnabled = false,
    this.setupCompleted = false,
    this.accountHolderName = '',
    this.legalName = '',
    this.accountType = '',
    this.bankLast4 = '',
    this.consentAcceptedAt,
    this.updatedAt,
  });

  static const String notStarted = 'NOT_STARTED';
  static const String pending = 'PENDING';
  static const String verified = 'VERIFIED';
  static const String actionRequired = 'ACTION_REQUIRED';
  static const String rejected = 'REJECTED';

  bool get isNotStarted =>
      !setupCompleted || onboardingStatus.toUpperCase() == notStarted;
  bool get isVerified => onboardingStatus.toUpperCase() == verified;
  bool get isPending => onboardingStatus.toUpperCase() == pending;
  bool get needsAction =>
      onboardingStatus.toUpperCase() == actionRequired ||
      onboardingStatus.toUpperCase() == rejected;

  bool get hasBank => bankLast4.isNotEmpty;

  /// Masked label, e.g. "•••• 4582", or null when nothing is stored yet.
  String? get maskedBank => hasBank ? '•••• $bankLast4' : null;

  String get statusLabel => switch (onboardingStatus.toUpperCase()) {
    verified => 'Verified',
    pending => 'Pending',
    actionRequired => 'Action required',
    rejected => 'Rejected',
    _ => 'Not completed',
  };

  /// Account-level settlement state. Stays "Not Enabled" until the provider
  /// (Razorpay Route) actually turns payouts on server-side — the app never
  /// advances this on its own.
  String get settlementLabel => settlementEnabled ? 'Enabled' : 'Not Enabled';

  factory OwnerPaymentAccount.fromJson(Map<String, dynamic> json) {
    DateTime? date(Object? v) {
      final s = v?.toString();
      return (s == null || s.trim().isEmpty) ? null : DateTime.tryParse(s);
    }

    return OwnerPaymentAccount(
      ownerId: json['ownerId']?.toString() ?? '',
      provider: (json['provider']?.toString() ?? '').trim().isEmpty
          ? 'RAZORPAY'
          : json['provider'].toString(),
      onboardingStatus:
          (json['onboardingStatus']?.toString() ?? '').trim().isEmpty
          ? notStarted
          : json['onboardingStatus'].toString().trim().toUpperCase(),
      settlementEnabled: json['settlementEnabled'] == true,
      setupCompleted: json['setupCompleted'] == true,
      accountHolderName: json['accountHolderName']?.toString() ?? '',
      legalName: json['legalName']?.toString() ?? '',
      accountType: json['accountType']?.toString() ?? '',
      bankLast4: json['bankLast4']?.toString() ?? '',
      consentAcceptedAt: date(json['consentAcceptedAt']),
      updatedAt: date(json['updatedAt']),
    );
  }
}

/// The owner-entered setup payload sent to
/// `PUT /api/payments/owner/payment-account`.
///
/// The full account number / IFSC live only in this request object on the
/// device: the backend validates them and stores them encrypted for an
/// administrator-executed payout, returning only a masked projection.
class OwnerPaymentAccountInput {
  final String legalName;
  final String accountType;
  final String mobile;
  final String email;
  final String accountHolderName;
  final String bankAccountNumber;
  final String confirmBankAccountNumber;
  final String ifscCode;
  final bool consent;

  const OwnerPaymentAccountInput({
    required this.legalName,
    required this.accountType,
    required this.mobile,
    required this.email,
    required this.accountHolderName,
    required this.bankAccountNumber,
    required this.confirmBankAccountNumber,
    required this.ifscCode,
    required this.consent,
  });

  Map<String, dynamic> toJson() => {
    'legalName': legalName,
    'accountType': accountType,
    'mobile': mobile,
    'email': email,
    'accountHolderName': accountHolderName,
    'bankAccountNumber': bankAccountNumber,
    'confirmBankAccountNumber': confirmBankAccountNumber,
    'ifscCode': ifscCode,
    'consent': consent,
  };
}
