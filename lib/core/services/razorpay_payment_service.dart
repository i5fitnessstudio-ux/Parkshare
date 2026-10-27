import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Outcome of one Razorpay Checkout session.
enum RazorpayCheckoutStatus {
  /// The user completed a payment. The values still MUST be verified by the
  /// backend before anything is marked paid.
  success,

  /// The user dismissed Checkout. Nothing was charged.
  cancelled,

  /// Checkout failed (network, invalid options, gateway error).
  failed,
}

/// Structured Checkout result handed back to the provider/UI.
///
/// SECURITY: [razorpaySignature] is only a *claim* produced by the app's
/// plugin. It is never trusted locally — it is sent to the backend, which
/// recomputes the HMAC with the key secret and is the only party that decides
/// whether the payment is real.
class RazorpayCheckoutResult {
  final RazorpayCheckoutStatus status;
  final String? razorpayOrderId;
  final String? razorpayPaymentId;
  final String? razorpaySignature;
  final String? message;

  const RazorpayCheckoutResult._({
    required this.status,
    this.razorpayOrderId,
    this.razorpayPaymentId,
    this.razorpaySignature,
    this.message,
  });

  factory RazorpayCheckoutResult.success({
    String? orderId,
    String? paymentId,
    String? signature,
  }) => RazorpayCheckoutResult._(
    status: RazorpayCheckoutStatus.success,
    razorpayOrderId: orderId,
    razorpayPaymentId: paymentId,
    razorpaySignature: signature,
  );

  factory RazorpayCheckoutResult.cancelled([String? message]) =>
      RazorpayCheckoutResult._(
        status: RazorpayCheckoutStatus.cancelled,
        message: message,
      );

  factory RazorpayCheckoutResult.failed(String? message) =>
      RazorpayCheckoutResult._(
        status: RazorpayCheckoutStatus.failed,
        message: message,
      );

  bool get isSuccess => status == RazorpayCheckoutStatus.success;
  bool get isCancelled => status == RazorpayCheckoutStatus.cancelled;
}

/// Thin, reusable wrapper around the official `razorpay_flutter` plugin.
///
/// One instance is created per [PaymentProvider]. Listeners are registered
/// exactly once and Checkout is driven through a [Completer] so the provider
/// awaits a single future per attempt and cannot be called back twice.
class RazorpayPaymentService {
  Razorpay? _razorpay;
  Completer<RazorpayCheckoutResult>? _completer;

  /// The order this client is currently allowed to complete.
  ///
  /// A plugin callback can arrive after the screen was reset or a different
  /// user signed in. Matching the callback to this id prevents an old
  /// Checkout result from completing a newer attempt.
  String? _expectedOrderId;

  /// Opens Checkout and resolves when the user finishes. Never throws; every
  /// platform outcome is mapped to a [RazorpayCheckoutResult].
  Future<RazorpayCheckoutResult> openCheckout({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String currency,
    required String parkingName,
    required String ownerName,
    required String bookingId,
    String? prefillEmail,
    String? prefillContact,
  }) async {
    final existing = _completer;
    if (existing != null && !existing.isCompleted) {
      return RazorpayCheckoutResult.failed(
        'A payment is already in progress. Please finish it first.',
      );
    }

    final completer = Completer<RazorpayCheckoutResult>();
    _completer = completer;
    _expectedOrderId = orderId;

    final options = <String, dynamic>{
      'key': keyId,
      // Checkout expects integer paise.
      'amount': amountPaise,
      'currency': currency,
      'order_id': orderId,
      'name': 'ParkShare',
      'description':
          'Parking booking'
          '${parkingName.isNotEmpty ? ' - $parkingName' : ''}',
      'theme': {'color': '#1F7A4D'},
      'notes': {
        'bookingId': bookingId,
        if (ownerName.isNotEmpty) 'ownerName': ownerName,
      },
      if (prefillEmail != null && prefillEmail.isNotEmpty)
        'prefill': {
          'email': prefillEmail,
          if (prefillContact != null && prefillContact.isNotEmpty)
            'contact': prefillContact,
        }
      else if (prefillContact != null && prefillContact.isNotEmpty)
        'prefill': {'contact': prefillContact},
    };

    try {
      _ensureInitialised();
      _razorpay!.open(options);
    } catch (e) {
      debugPrint('[Razorpay] open failed: ${e.runtimeType}');
      _complete(RazorpayCheckoutResult.failed('Could not open Razorpay.'));
    }
    return completer.future;
  }

  void _ensureInitialised() {
    if (_razorpay != null) return;
    final razorpay = Razorpay();
    // Registered once per plugin instance: no duplicate listeners, no leaks.
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _razorpay = razorpay;
  }

  void _onSuccess(dynamic response) {
    if (response is PaymentSuccessResponse) {
      _completeSuccess(
        orderId: response.orderId,
        paymentId: response.paymentId,
        signature: response.signature,
      );
      return;
    }
    if (response is Map) {
      _completeSuccess(
        orderId: response['razorpay_order_id']?.toString(),
        paymentId: response['razorpay_payment_id']?.toString(),
        signature: response['razorpay_signature']?.toString(),
      );
      return;
    }
    _complete(
      RazorpayCheckoutResult.failed(
        'Razorpay returned an unexpected response.',
      ),
    );
  }

  void _completeSuccess({
    String? orderId,
    String? paymentId,
    String? signature,
  }) {
    final expected = _expectedOrderId;
    // Drop a stale callback from a previous order instead of completing the
    // current attempt with someone else's payment.
    if (expected != null &&
        orderId != null &&
        orderId.isNotEmpty &&
        orderId != expected) {
      debugPrint('[Razorpay] ignored success for a stale order');
      return;
    }
    _complete(
      RazorpayCheckoutResult.success(
        orderId: orderId,
        paymentId: paymentId,
        signature: signature,
      ),
    );
  }

  void _onError(dynamic response) {
    var code = Razorpay.UNKNOWN_ERROR;
    var message = 'Payment failed. Please try again.';
    if (response is PaymentFailureResponse) {
      code = response.code ?? Razorpay.UNKNOWN_ERROR;
      message = response.message?.toString() ?? message;
    } else if (response is Map) {
      code = (response['code'] as num?)?.toInt() ?? Razorpay.UNKNOWN_ERROR;
      message = response['message']?.toString() ?? message;
    }
    if (code == Razorpay.PAYMENT_CANCELLED) {
      _complete(RazorpayCheckoutResult.cancelled('Payment cancelled.'));
      return;
    }
    _complete(RazorpayCheckoutResult.failed(message));
  }

  void _onExternalWallet(dynamic response) {
    // The user was redirected into an external wallet (e.g. a wallet app). The
    // final outcome arrives through the success/error events, so surface an
    // informational failure only if Checkout never returns.
    final wallet = response is ExternalWalletResponse
        ? response.walletName
        : (response is Map ? response['external_wallet']?.toString() : null);
    debugPrint('[Razorpay] external wallet selected: ${wallet ?? "unknown"}');
  }

  void _complete(RazorpayCheckoutResult result) {
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    _completer = null;
    _expectedOrderId = null;
    completer.complete(result);
  }

  /// Cancels an in-flight Checkout future and drops its plugin listeners.
  ///
  /// Used when the authenticated account actually changes, or when the owning
  /// provider is disposed. The future must complete: the original code only
  /// nulled the completer, so `await openCheckout(...)` could hang forever and
  /// leave the screen stuck on "processing". Calling this when nothing is open
  /// is harmless.
  void cancelPending({String? message}) {
    final completer = _completer;
    _completer = null;
    _expectedOrderId = null;
    // Drop callbacks from the abandoned Checkout session. A later attempt gets
    // a fresh plugin instance and fresh listeners.
    _razorpay?.clear();
    _razorpay = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(
        RazorpayCheckoutResult.cancelled(
          message ?? 'Payment cancelled. Please try again.',
        ),
      );
    }
  }

  /// Releases plugin listeners. Call from the provider's `dispose`.
  void dispose() {
    cancelPending(message: 'Payment session ended. Please try again.');
  }
}
