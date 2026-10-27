import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/booking.dart';
import '../../shared/models/owner_payment_info.dart';
import '../../shared/models/razorpay_order.dart';

/// Payment API — **online (Razorpay) and Cash on Delivery**.
///
/// Every method maps 1:1 to an existing backend endpoint; no rules are
/// duplicated on the client. The backend stays authoritative: it owns the
/// booking/payment state machine, the owner payment snapshot, the Razorpay
/// signature verification and the earnings.
class PaymentService {
  final ApiClient _client;

  PaymentService({ApiClient? client}) : _client = client ?? ApiClient();

  /// Owner contact details for the SELECTED parking listing.
  ///
  /// Drives the payment screen's owner block and the COD "call the owner"
  /// affordance.
  Future<OwnerPaymentInfo> fetchOwnerPaymentInfo({
    required String token,
    required String parkingId,
  }) async {
    final data = await _client.get(
      ApiConstants.parkingOwnerPaymentInfo(parkingId),
      token: token,
    );
    return OwnerPaymentInfo.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// Cash on Delivery: booking becomes COD_PENDING and RELEASES its slot, so
  /// the parking stays available until the owner confirms the cash.
  Future<Booking> createCod({
    required String token,
    required String bookingId,
  }) async {
    final data = await _client.post(
      ApiConstants.cod,
      body: {'bookingId': bookingId},
      token: token,
    );
    return Booking.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// Owner side: the cash was handed over → slot allocated, booking CONFIRMED,
  /// payment COD_CONFIRMED and the amount enters the owner's Total Earnings.
  Future<Booking> confirmCod({
    required String token,
    required String bookingId,
  }) async {
    final data = await _client.put(
      ApiConstants.confirmCod(bookingId),
      token: token,
    );
    return Booking.fromJson((data as Map<String, dynamic>?) ?? {});
  }

  /// Authoritative owner settlement totals, computed by the backend in SQL.
  ///
  /// AUDIT C-02: this replaces the client-side `amount` sum. The dashboard used
  /// to derive "Total Earnings" from whichever page of bookings it had loaded,
  /// which is a money figure no other party could check.
  Future<OwnerEarningsSummary> fetchOwnerEarnings({
    required String token,
  }) async {
    final data = await _client.get(ApiConstants.ownerEarnings, token: token);
    return OwnerEarningsSummary.fromJson(
      (data as Map<String, dynamic>?) ?? const {},
    );
  }

  /// Loads the authenticated owner's masked payment/settlement account.
  ///
  /// Owner-only. The backend derives the owner from the JWT; no owner id is
  /// sent. The response is masked (bank last-4 only) and is safe to render.
  Future<OwnerPaymentAccount> fetchOwnerPaymentAccount({
    required String token,
  }) async {
    final data = await _client.get(
      ApiConstants.ownerPaymentAccount,
      token: token,
    );
    return OwnerPaymentAccount.fromJson(
      (data as Map<String, dynamic>?) ?? const {},
    );
  }

  /// Saves the authenticated owner's payout setup.
  ///
  /// The full account number / IFSC travel only in this request; the backend
  /// validates them and stores them AES-256-GCM encrypted for a manual payout,
  /// while the owner-facing response exposes only the last four digits. The server records
  /// the setup as PENDING until provider onboarding confirms it — this call
  /// never marks settlement as enabled.
  Future<OwnerPaymentAccount> saveOwnerPaymentAccount({
    required String token,
    required OwnerPaymentAccountInput input,
  }) async {
    final data = await _client.put(
      ApiConstants.ownerPaymentAccount,
      body: input.toJson(),
      token: token,
    );
    return OwnerPaymentAccount.fromJson(
      (data as Map<String, dynamic>?) ?? const {},
    );
  }

  // ---- Razorpay online payment ---------------------------------------
  //
  // The amount is NEVER sent from here: the backend reads it from the booking
  // row. This service only transports the order request and the Checkout
  // result; the server is the only party that verifies a signature and decides
  // whether a booking is paid.

  /// Creates a server-authoritative Razorpay order for [bookingId].
  ///
  /// Returns only public Checkout data — the Razorpay **key id**, the order id
  /// and the integer `amount` in paise. The key secret never leaves the server.
  Future<RazorpayOrder> createRazorpayOrder({
    required String token,
    required String bookingId,
  }) async {
    final data = await _client.post(
      ApiConstants.razorpayOrder,
      body: {'bookingId': bookingId},
      token: token,
    );
    return RazorpayOrder.fromJson((data as Map<String, dynamic>?) ?? const {});
  }

  /// Verifies a Razorpay Checkout callback on the backend and returns the
  /// booking when the server has accepted it.
  ///
  /// SECURITY: signature verification happens ONLY on the backend. The values
  /// sent here are the plugin's *claims*; they are useless to anyone without
  /// the server-side key secret. A successful HTTP response means the server
  /// verified the HMAC (or a webhook already did) — never that "the app said so".
  Future<Booking> verifyRazorpayPayment({
    required String token,
    required String bookingId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final data = await _client.post(
      ApiConstants.razorpayVerify,
      body: {
        'bookingId': bookingId,
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
      },
      token: token,
    );
    return Booking.fromJson((data as Map<String, dynamic>?) ?? const {});
  }

  /// Owner contact block for the COD screen, read off a booking payload.
  ///
  /// The COD endpoint returns the booking plus an `ownerContact` object; this
  /// keeps that mapping in one place.
  static OwnerContact ownerContactFromBooking(Booking booking) => OwnerContact(
    name: booking.ownerName,
    phone: booking.ownerPhone,
    upiId: booking.ownerUpiId,
    parkingName: booking.parking.name,
    address: booking.parking.address,
  );
}
