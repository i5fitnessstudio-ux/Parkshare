/// Public data returned by `POST /api/payments/razorpay/order`.
///
/// Only what Razorpay Checkout needs plus display labels. The Razorpay **key
/// secret** is server-only and is never present in this payload.
class RazorpayOrder {
  /// Local `payments.id` for this attempt.
  final String paymentId;

  /// The booking being paid.
  final String bookingId;

  /// Razorpay order id (`order_…`).
  final String razorpayOrderId;

  /// Public Razorpay key id used by Checkout. Safe to expose.
  final String razorpayKeyId;

  /// Amount in **integer paise** (e.g. ₹500.00 → 50000).
  final int amountPaise;

  /// ISO currency code, always `INR` for ParkShare.
  final String currency;

  final String ownerName;
  final String parkingName;

  const RazorpayOrder({
    required this.paymentId,
    required this.bookingId,
    required this.razorpayOrderId,
    required this.razorpayKeyId,
    required this.amountPaise,
    required this.currency,
    this.ownerName = '',
    this.parkingName = '',
  });

  factory RazorpayOrder.fromJson(Map<String, dynamic> json) {
    return RazorpayOrder(
      paymentId: json['paymentId']?.toString() ?? '',
      bookingId: json['bookingId']?.toString() ?? '',
      razorpayOrderId: json['razorpayOrderId']?.toString() ?? '',
      razorpayKeyId: json['razorpayKeyId']?.toString() ?? '',
      amountPaise: (json['amount'] as num?)?.toInt() ?? 0,
      currency: json['currency']?.toString() ?? 'INR',
      ownerName: json['ownerName']?.toString() ?? '',
      parkingName: json['parkingName']?.toString() ?? '',
    );
  }

  /// True when the payload is complete enough to open Checkout.
  bool get isUsable =>
      razorpayKeyId.isNotEmpty &&
      razorpayOrderId.isNotEmpty &&
      amountPaise > 0;
}
