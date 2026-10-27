import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/core/services/payment_service.dart';
import 'package:parkshare_new/core/services/razorpay_payment_service.dart';
import 'package:parkshare_new/modules/booking/providers/payment_provider.dart';
import 'package:parkshare_new/shared/models/booking.dart';
import 'package:parkshare_new/shared/models/razorpay_order.dart';

/// Razorpay Checkout is a platform plugin, so it cannot run in a unit test.
/// This fake gives the provider a controllable in-flight session.
class _FakeCheckout extends RazorpayPaymentService {
  Completer<RazorpayCheckoutResult>? _pending;
  bool cancelCalled = false;
  int openCount = 0;

  bool get isOpen => _pending != null && !_pending!.isCompleted;

  @override
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
  }) {
    openCount++;
    _pending = Completer<RazorpayCheckoutResult>();
    return _pending!.future;
  }

  void completeSuccess({required String orderId, required String paymentId}) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(
        RazorpayCheckoutResult.success(
          orderId: orderId,
          paymentId: paymentId,
          signature: 'test-signature',
        ),
      );
    }
  }

  @override
  void cancelPending({String? message}) {
    cancelCalled = true;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(
        RazorpayCheckoutResult.cancelled(message ?? 'cancelled'),
      );
    }
  }

  @override
  void dispose() => cancelPending();
}

class _FakePaymentApi extends PaymentService {
  _FakePaymentApi({
    required this.verifyCompleter,
    this.verifyResponses = const [],
  });

  final Completer<Booking> verifyCompleter;

  /// Optional per-call verification results. When exhausted, the test's
  /// [verifyCompleter] controls the response instead.
  final List<Booking> verifyResponses;
  int createOrderCalls = 0;
  int verifyCalls = 0;

  @override
  Future<RazorpayOrder> createRazorpayOrder({
    required String token,
    required String bookingId,
  }) async {
    createOrderCalls++;
    return const RazorpayOrder(
      paymentId: 'payment-1',
      bookingId: 'booking-1',
      razorpayOrderId: 'order_1',
      razorpayKeyId: 'rzp_test_public',
      amountPaise: 50000,
      currency: 'INR',
    );
  }

  @override
  Future<Booking> verifyRazorpayPayment({
    required String token,
    required String bookingId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) {
    verifyCalls++;
    if (verifyCalls <= verifyResponses.length) {
      return Future.value(verifyResponses[verifyCalls - 1]);
    }
    return verifyCompleter.future;
  }
}

Booking _paidBooking() => Booking.fromJson({
  'bookingId': 'booking-1',
  'status': BookingStatus.confirmed,
  'paymentMethod': PaymentMethod.razorpay,
  'paymentStatus': PaymentStatus.success,
});

Booking _unverifiedBooking() => Booking.fromJson({
  'bookingId': 'booking-1',
  'status': BookingStatus.confirmed,
  'paymentMethod': PaymentMethod.razorpay,
  'paymentStatus': PaymentStatus.pending,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account switch completes an open Checkout as cancelled and does not verify', () async {
    final checkout = _FakeCheckout();
    final api = _FakePaymentApi(verifyCompleter: Completer<Booking>());
    final provider = PaymentProvider(service: api, checkout: checkout);

    final pending = provider.startRazorpayPayment(
      token: 'token',
      bookingId: 'booking-1',
    );
    await Future<void>.delayed(Duration.zero);
    expect(checkout.isOpen, isTrue);

    provider.resetForAccountSwitch();
    final result = await pending;

    expect(result.outcome, RazorpayOutcome.cancelled);
    expect(checkout.cancelCalled, isTrue);
    expect(api.verifyCalls, 0);
    expect(provider.paidBooking, isNull);
    expect(provider.step, PaymentStep.choosing);
    expect(provider.processing, isFalse);
  });

  test('a verification response for the previous account cannot mark a booking paid', () async {
    final checkout = _FakeCheckout();
    final verify = Completer<Booking>();
    final api = _FakePaymentApi(verifyCompleter: verify);
    final provider = PaymentProvider(service: api, checkout: checkout);

    final pending = provider.startRazorpayPayment(
      token: 'token',
      bookingId: 'booking-1',
    );
    await Future<void>.delayed(Duration.zero);
    checkout.completeSuccess(orderId: 'order_1', paymentId: 'pay_1');
    await Future<void>.delayed(Duration.zero);
    expect(api.verifyCalls, 1);

    provider.resetForAccountSwitch();
    verify.complete(_paidBooking());
    final result = await pending;

    expect(result.outcome, RazorpayOutcome.cancelled);
    expect(provider.paidBooking, isNull);
    expect(provider.step, PaymentStep.choosing);
    expect(provider.processing, isFalse);
  });

  test(
    'a pending Checkout claim is re-verified instead of opening a second order',
    () async {
      final checkout = _FakeCheckout();
      final api = _FakePaymentApi(
        verifyCompleter: Completer<Booking>(),
        verifyResponses: [_unverifiedBooking(), _paidBooking()],
      );
      final provider = PaymentProvider(service: api, checkout: checkout);

      final firstAttempt = provider.startRazorpayPayment(
        token: 'token',
        bookingId: 'booking-1',
      );
      await Future<void>.delayed(Duration.zero);
      expect(checkout.openCount, 1);
      expect(api.createOrderCalls, 1);

      checkout.completeSuccess(orderId: 'order_1', paymentId: 'pay_1');
      final firstResult = await firstAttempt;
      expect(firstResult.outcome, RazorpayOutcome.pendingVerification);
      expect(api.verifyCalls, 1);

      // The user dismissed the "verifying" dialog and pressed Pay again. The
      // provider must verify the existing claim, not charge a second order.
      final secondResult = await provider.startRazorpayPayment(
        token: 'token',
        bookingId: 'booking-1',
      );

      expect(secondResult.outcome, RazorpayOutcome.paid);
      expect(api.createOrderCalls, 1);
      expect(api.verifyCalls, 2);
      expect(checkout.openCount, 1);
      expect(provider.paidBooking?.bookingId, 'booking-1');
    },
  );

  test('dispose completes an in-flight Checkout future', () async {
    final checkout = _FakeCheckout();
    final api = _FakePaymentApi(verifyCompleter: Completer<Booking>());
    final provider = PaymentProvider(service: api, checkout: checkout);

    final pending = provider.startRazorpayPayment(
      token: 'token',
      bookingId: 'booking-1',
    );
    await Future<void>.delayed(Duration.zero);
    provider.dispose();

    final result = await pending.timeout(const Duration(seconds: 1));
    expect(result.outcome, RazorpayOutcome.cancelled);
  });
}
