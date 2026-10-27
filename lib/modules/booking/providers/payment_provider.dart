import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/services/payment_service.dart';
import '../../../core/services/razorpay_payment_service.dart';
import '../../../shared/models/booking.dart';
import '../../../shared/models/owner_payment_info.dart';
import '../../../shared/models/razorpay_order.dart';

/// Where the payment screen currently is in the online / COD decision.
enum PaymentStep {
  /// Choosing between online (Razorpay) and Cash on Delivery.
  choosing,

  /// COD chosen — waiting for the owner to confirm the cash.
  codPending,

  /// Razorpay Checkout is open, or the backend is verifying its result.
  awaitingRazorpay,

  /// The backend verified the online payment: the booking is PAID/CONFIRMED.
  onlinePaid,

  /// Checkout reported a payment but the backend has not confirmed it yet
  /// (network failure, or the webhook has not arrived). Deliberately *not*
  /// success: nothing is marked paid locally, and the user must not pay again.
  onlinePendingVerification,
}

/// Outcome of one online (Razorpay) payment attempt.
enum RazorpayOutcome {
  /// The backend verified the payment and the booking is PAID.
  paid,

  /// Could not even start (not configured, conflicting status, already paid…),
  /// or the backend definitively rejected the result.
  rejected,

  /// The user dismissed Checkout; nothing was charged.
  cancelled,

  /// Checkout reported a payment, but the backend has not confirmed it yet.
  /// Non-destructive: the attempt can be re-verified without paying again.
  pendingVerification,
}

/// Result of an online "Pay Now" attempt.
///
/// The screen always gets an explicit outcome and a reason, so a failure can
/// never render as a silent no-op.
class RazorpayStartResult {
  final RazorpayOutcome outcome;

  /// User-facing explanation when [outcome] is not [RazorpayOutcome.paid].
  final String? message;

  /// The booking the **backend** returned once it verified the payment.
  final Booking? booking;

  RazorpayStartResult._(this.outcome, {this.message, this.booking});

  factory RazorpayStartResult.paid(Booking booking) =>
      RazorpayStartResult._(RazorpayOutcome.paid, booking: booking);

  factory RazorpayStartResult.rejected(String message) =>
      RazorpayStartResult._(RazorpayOutcome.rejected, message: message);

  factory RazorpayStartResult.cancelled(String message) =>
      RazorpayStartResult._(RazorpayOutcome.cancelled, message: message);

  factory RazorpayStartResult.pendingVerification({String? message}) =>
      RazorpayStartResult._(
        RazorpayOutcome.pendingVerification,
        message: message,
      );

  bool get isPaid => outcome == RazorpayOutcome.paid;
}

/// State for the online (Razorpay) + Cash-on-Delivery payment flow.
///
/// Owns only presentation state; the backend owns every rule (who may pay,
/// when a booking is confirmed, what counts as earnings). Each call here maps
/// to exactly one existing endpoint.
class PaymentProvider extends ChangeNotifier {
  final PaymentService _service;
  final RazorpayPaymentService _checkout;

  OwnerPaymentInfo? _ownerInfo;
  bool _loadingOwnerInfo = false;

  String _method = PaymentMethod.online;
  bool _processing = false;
  String? _error;
  Booking? _paidBooking;
  PaymentStep _step = PaymentStep.choosing;

  /// The unverified Checkout claim, kept so a failed verification can be
  /// retried without asking the user to pay a second time.
  String? _pendingRazorpayOrderId;
  String? _pendingRazorpayPaymentId;
  String? _pendingRazorpaySignature;

  /// The booking the pending Checkout claim belongs to. Checkout state is
  /// global to this provider, so the booking id prevents an unverified claim
  /// from one booking being retried against another.
  String? _pendingRazorpayBookingId;

  bool get _hasVerifiablePendingClaim =>
      (_pendingRazorpayOrderId ?? '').isNotEmpty &&
      (_pendingRazorpayPaymentId ?? '').isNotEmpty &&
      (_pendingRazorpaySignature ?? '').isNotEmpty;

  /// Incremented whenever session-bound state is cleared (account switch,
  /// explicit reset, dispose). Async work captures it and refuses to write
  /// results after the epoch changed, so a late API response for the previous
  /// account can never repopulate the new account's screen.
  int _sessionEpoch = 0;

  bool _isCurrent(int epoch) => epoch == _sessionEpoch;

  PaymentProvider({PaymentService? service, RazorpayPaymentService? checkout})
    : _service = service ?? PaymentService(),
      _checkout = checkout ?? RazorpayPaymentService();

  // ---- Reads ----
  OwnerPaymentInfo? get ownerInfo => _ownerInfo;
  bool get loadingOwnerInfo => _loadingOwnerInfo;
  String get method => _method;
  bool get processing => _processing;
  String? get error => _error;
  Booking? get paidBooking => _paidBooking;
  PaymentStep get step => _step;

  /// True while Razorpay Checkout is open or the backend is verifying.
  bool get isAwaitingRazorpay => _step == PaymentStep.awaitingRazorpay;

  /// True once the backend has verified an online payment.
  bool get onlinePaid => _step == PaymentStep.onlinePaid;

  /// True when Checkout reported a payment the backend has not confirmed yet.
  bool get needsOnlineVerification =>
      _step == PaymentStep.onlinePendingVerification;

  /// The owner contact block for the COD screen.
  OwnerContact get ownerContact => _ownerInfo == null
      ? const OwnerContact(name: '', parkingName: '', address: '')
      : OwnerContact(
          name: _ownerInfo!.ownerName,
          phone: _ownerInfo!.ownerPhone,
          upiId: _ownerInfo!.ownerUpiId,
          parkingName: _ownerInfo!.parkingName,
          address: _ownerInfo!.address,
        );

  /// The methods the production screen offers: Razorpay online payment and Cash
  /// on Delivery. The legacy direct-UPI option is intentionally not listed.
  List<String> get availableMethods => const [
    PaymentMethod.online,
    PaymentMethod.cod,
  ];

  // ---- Owner info ----

  /// Loads the selected owner's UPI id + contact details.
  ///
  /// A failure is NOT fatal: the screen falls back to the booking's own owner
  /// data, and COD still works without a UPI id.
  Future<void> loadOwnerInfo({
    required String token,
    required String parkingId,
  }) async {
    if (parkingId.isEmpty) return;
    final epoch = _sessionEpoch;
    _loadingOwnerInfo = true;
    _error = null;
    notifyListeners();
    try {
      final info = await _service.fetchOwnerPaymentInfo(
        token: token,
        parkingId: parkingId,
      );
      if (!_isCurrent(epoch)) return;
      _ownerInfo = info;
      // The online (Razorpay) method is always offered, so the selection is not
      // changed when owner details load — that would fight a manual COD choice.
    } on ApiException catch (e) {
      ErrorMessages.logTechnical('ownerPaymentInfo', e);
      if (_isCurrent(epoch)) _ownerInfo = null;
    } catch (e) {
      ErrorMessages.logTechnical('ownerPaymentInfo', e);
      if (_isCurrent(epoch)) _ownerInfo = null;
    } finally {
      if (_isCurrent(epoch)) {
        _loadingOwnerInfo = false;
        notifyListeners();
      }
    }
  }

  void selectMethod(String method) {
    final value = method.trim().toUpperCase();
    if (!PaymentMethod.selectable.contains(value)) return;
    if (_method == value) return;
    _method = value;
    _error = null;
    notifyListeners();
  }

  // ---- Online payment (Razorpay) ----

  /// Runs one online-payment attempt end to end:
  ///   1. ask the backend for a server-authoritative order (the amount comes
  ///      from the booking row, never from here),
  ///   2. open Razorpay Checkout,
  ///   3. send the Checkout result back for signature verification.
  ///
  /// The app never decides that a payment succeeded: [paidBooking] is set only
  /// from the booking the backend returns *after* it verified the signature (or
  /// a webhook already did).
  Future<RazorpayStartResult> startRazorpayPayment({
    required String token,
    required String bookingId,
    String? prefillEmail,
    String? prefillContact,
  }) async {
    if (_processing) {
      return RazorpayStartResult.rejected(
        'A payment is already in progress. Please wait a moment.',
      );
    }
    // Never create a second order for a booking whose last Checkout result has
    // not been confirmed yet: the user may already have been charged. Re-run
    // verification with the stored claim instead.
    if (_pendingRazorpayBookingId == bookingId) {
      if (_hasVerifiablePendingClaim) {
        return retryVerify(token: token, bookingId: bookingId);
      }
      return RazorpayStartResult.pendingVerification(
        message:
            'A payment for this booking is still awaiting confirmation. '
            'Refresh the status; do not pay again.',
      );
    }
    final epoch = _sessionEpoch;
    _processing = true;
    _error = null;
    _step = PaymentStep.choosing;
    notifyListeners();
    try {
      final RazorpayOrder order;
      try {
        order = await _service.createRazorpayOrder(
          token: token,
          bookingId: bookingId,
        );
      } on ApiException catch (e) {
        ErrorMessages.logTechnical('razorpayOrder', e);
        _error = _readable(e, fallback: 'Online payment could not be started.');
        _step = PaymentStep.choosing;
        return RazorpayStartResult.rejected(_error!);
      } catch (e) {
        ErrorMessages.logTechnical('razorpayOrder', e);
        _error = 'Online payment could not be started. Please try again.';
        _step = PaymentStep.choosing;
        return RazorpayStartResult.rejected(_error!);
      }

      if (!_isCurrent(epoch)) {
        return RazorpayStartResult.cancelled(
          'The signed-in account changed before payment started.',
        );
      }

      if (!order.isUsable) {
        _error =
            'Online payment is not available right now. Please use Cash on '
            'Delivery or try again later.';
        _step = PaymentStep.choosing;
        return RazorpayStartResult.rejected(_error!);
      }

      // Remember the order id up front: the signature we later verify is bound
      // to THIS order, even if the plugin echoes a different one.
      _pendingRazorpayOrderId = order.razorpayOrderId;
      _pendingRazorpayPaymentId = null;
      _pendingRazorpaySignature = null;
      _pendingRazorpayBookingId = bookingId;

      _step = PaymentStep.awaitingRazorpay;
      notifyListeners();

      final result = await _checkout.openCheckout(
        keyId: order.razorpayKeyId,
        orderId: order.razorpayOrderId,
        amountPaise: order.amountPaise,
        currency: order.currency,
        parkingName: order.parkingName,
        ownerName: order.ownerName,
        bookingId: bookingId,
        prefillEmail: prefillEmail,
        prefillContact: prefillContact,
      );

      if (!_isCurrent(epoch)) {
        return RazorpayStartResult.cancelled(
          'The signed-in account changed during payment.',
        );
      }

      if (result.isCancelled) {
        _clearPendingRazorpay();
        _step = PaymentStep.choosing;
        return RazorpayStartResult.cancelled('Payment cancelled.');
      }
      if (!result.isSuccess) {
        _clearPendingRazorpay();
        _error = result.message ?? 'Payment failed. Please try again.';
        _step = PaymentStep.choosing;
        return RazorpayStartResult.rejected(_error!);
      }

      // The plugin's values are claims only. Keep them so the backend can
      // verify — or so a transient failure can be retried without repaying.
      _pendingRazorpayOrderId =
          result.razorpayOrderId ?? _pendingRazorpayOrderId;
      _pendingRazorpayPaymentId = result.razorpayPaymentId;
      _pendingRazorpaySignature = result.razorpaySignature;

      return await _verifyOnline(
        token: token,
        bookingId: bookingId,
        epoch: epoch,
      );
    } finally {
      if (_isCurrent(epoch)) {
        _processing = false;
        notifyListeners();
      }
    }
  }

  /// Re-runs backend verification for the last Checkout claim.
  ///
  /// Used when the first verification could not complete (e.g. a network drop).
  /// It never asks the user to pay again: the claim is kept until confirmed.
  Future<RazorpayStartResult> retryVerify({
    required String token,
    required String bookingId,
  }) async {
    if (_processing) {
      return RazorpayStartResult.rejected('Please wait a moment.');
    }
    if (_pendingRazorpayBookingId != null &&
        _pendingRazorpayBookingId != bookingId) {
      return RazorpayStartResult.rejected(
        'There is no payment awaiting verification for this booking.',
      );
    }
    if ((_pendingRazorpayPaymentId ?? '').isEmpty ||
        (_pendingRazorpaySignature ?? '').isEmpty) {
      return RazorpayStartResult.rejected(
        'There is no payment awaiting verification.',
      );
    }
    final epoch = _sessionEpoch;
    _processing = true;
    _error = null;
    notifyListeners();
    try {
      return await _verifyOnline(
        token: token,
        bookingId: bookingId,
        epoch: epoch,
      );
    } finally {
      if (_isCurrent(epoch)) {
        _processing = false;
        notifyListeners();
      }
    }
  }

  Future<RazorpayStartResult> _verifyOnline({
    required String token,
    required String bookingId,
    required int epoch,
  }) async {
    final orderId = _pendingRazorpayOrderId ?? '';
    final paymentId = _pendingRazorpayPaymentId ?? '';
    final signature = _pendingRazorpaySignature ?? '';
    if (orderId.isEmpty || paymentId.isEmpty || signature.isEmpty) {
      // Checkout claimed success but handed back nothing verifiable. Do not
      // claim success; a webhook may still confirm it.
      _step = PaymentStep.onlinePendingVerification;
      return RazorpayStartResult.pendingVerification(
        message: 'We are still confirming your payment with Razorpay.',
      );
    }

    _step = PaymentStep.awaitingRazorpay;
    notifyListeners();
    try {
      final booking = await _service.verifyRazorpayPayment(
        token: token,
        bookingId: bookingId,
        razorpayOrderId: orderId,
        razorpayPaymentId: paymentId,
        razorpaySignature: signature,
      );
      if (!_isCurrent(epoch)) {
        return RazorpayStartResult.cancelled(
          'The signed-in account changed while the payment was verified.',
        );
      }
      _paidBooking = booking;
      if (booking.isPaymentComplete) {
        _clearPendingRazorpay();
        _step = PaymentStep.onlinePaid;
        return RazorpayStartResult.paid(booking);
      }
      _step = PaymentStep.onlinePendingVerification;
      return RazorpayStartResult.pendingVerification(
        message: 'Your payment is being confirmed. Please check back shortly.',
      );
    } on ApiException catch (e) {
      ErrorMessages.logTechnical('razorpayVerify', e);
      if (!_isCurrent(epoch)) {
        return RazorpayStartResult.cancelled(
          'The signed-in account changed while the payment was verified.',
        );
      }
      // A definitive rejection (bad signature / unknown order / conflict) is a
      // hard failure. A transient one leaves the attempt pending so it can be
      // re-verified.
      if (e.type == ApiErrorType.validation ||
          e.type == ApiErrorType.notFound ||
          e.type == ApiErrorType.conflict ||
          e.type == ApiErrorType.authorization) {
        // A definitive rejection cannot be healed by retrying this claim.
        _clearPendingRazorpay();
        _step = PaymentStep.choosing;
        _error = _readable(
          e,
          fallback:
              'Payment could not be verified. If money was deducted, contact '
              'support with your booking reference.',
        );
        return RazorpayStartResult.rejected(_error!);
      }
      _step = PaymentStep.onlinePendingVerification;
      return RazorpayStartResult.pendingVerification(
        message:
            'We could not confirm your payment yet. Do not pay again — refresh '
            'in a moment.',
      );
    } catch (e) {
      ErrorMessages.logTechnical('razorpayVerify', e);
      if (!_isCurrent(epoch)) {
        return RazorpayStartResult.cancelled(
          'The signed-in account changed while the payment was verified.',
        );
      }
      _step = PaymentStep.onlinePendingVerification;
      return RazorpayStartResult.pendingVerification(
        message:
            'We could not confirm your payment yet. Do not pay again — refresh '
            'in a moment.',
      );
    }
  }

  void _clearPendingRazorpay() {
    _pendingRazorpayOrderId = null;
    _pendingRazorpayPaymentId = null;
    _pendingRazorpaySignature = null;
    _pendingRazorpayBookingId = null;
  }

  // ---- COD ----

  /// Cash on Delivery: booking becomes COD_PENDING, the slot stays available
  /// and no money counts as earned until the owner confirms.
  Future<bool> startCod({
    required String token,
    required String bookingId,
  }) async {
    if (_processing) return false;
    final epoch = _sessionEpoch;
    _processing = true;
    _error = null;
    notifyListeners();
    try {
      final booking = await _service.createCod(
        token: token,
        bookingId: bookingId,
      );
      if (!_isCurrent(epoch)) return false;
      _paidBooking = booking;
      _step = PaymentStep.codPending;
      return true;
    } on ApiException catch (e) {
      ErrorMessages.logTechnical('createCod', e);
      if (!_isCurrent(epoch)) return false;
      _error = _readable(e, fallback: 'Cash on Delivery could not be set up.');
      _step = PaymentStep.choosing;
      return false;
    } catch (e) {
      ErrorMessages.logTechnical('createCod', e);
      if (!_isCurrent(epoch)) return false;
      _error = 'Cash on Delivery could not be set up. Please try again.';
      _step = PaymentStep.choosing;
      return false;
    } finally {
      if (_isCurrent(epoch)) {
        _processing = false;
        notifyListeners();
      }
    }
  }

  // ---- Owner side ----

  /// Owner marks the cash received: slot allocated, booking CONFIRMED,
  /// payment COD_CONFIRMED and the amount enters the owner's Total Earnings.
  Future<bool> confirmCod({
    required String token,
    required String bookingId,
  }) async {
    if (_processing) return false;
    final epoch = _sessionEpoch;
    _processing = true;
    _error = null;
    notifyListeners();
    try {
      final booking = await _service.confirmCod(
        token: token,
        bookingId: bookingId,
      );
      if (!_isCurrent(epoch)) return false;
      _paidBooking = booking;
      return true;
    } on ApiException catch (e) {
      ErrorMessages.logTechnical('confirmCod', e);
      if (!_isCurrent(epoch)) return false;
      _error = ErrorMessages.forUi(
        e,
        fallback: 'Could not confirm the cash payment. Please try again.',
      );
      return false;
    } catch (e) {
      ErrorMessages.logTechnical('confirmCod', e);
      if (!_isCurrent(epoch)) return false;
      _error = 'Could not confirm the cash payment. Please try again.';
      return false;
    } finally {
      if (_isCurrent(epoch)) {
        _processing = false;
        notifyListeners();
      }
    }
  }

  String _readable(ApiException e, {required String fallback}) =>
      ErrorMessages.forUi(e, fallback: fallback);

  /// Clears a one-shot error (after it has been shown).
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  /// Returns the screen to the initial state and abandons any in-flight
  /// Checkout/verification work.
  void reset() {
    _sessionEpoch++;
    try {
      _checkout.cancelPending(message: 'Payment reset. Please try again.');
    } catch (_) {}
    _clearSessionState();
    notifyListeners();
  }

  /// Resets all payment state when the authenticated identity changes.
  ///
  /// This is called only on an actual login/account switch, never on every app
  /// rebuild. It cancels Checkout so its future completes, rather than merely
  /// nulling the completer and leaving the caller waiting forever.
  void resetForAccountSwitch() {
    _sessionEpoch++;
    try {
      _checkout.cancelPending(message: 'Signed in as a different account.');
    } catch (_) {}
    _clearSessionState();
    notifyListeners();
  }

  void _clearSessionState() {
    _paidBooking = null;
    _error = null;
    _step = PaymentStep.choosing;
    _method = PaymentMethod.online;
    _clearPendingRazorpay();
    _loadingOwnerInfo = false;
    _ownerInfo = null;
    _processing = false;
  }

  @override
  void dispose() {
    // Invalidate async work first, then release plugin listeners. Any waiting
    // Checkout future is completed as cancelled by `dispose`.
    _sessionEpoch++;
    _checkout.dispose();
    super.dispose();
  }
}
