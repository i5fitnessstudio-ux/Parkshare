import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/shared/models/booking.dart';
import 'package:parkshare_new/shared/models/razorpay_order.dart';
import 'package:parkshare_new/shared/utils/booking_ui.dart';

/// Locks in the client-side Razorpay contract:
///  * the create-order payload is parsed into integer paise and is only usable
///    when it carries a key id, an order id and a positive amount;
///  * `ONLINE` is a UI selection token, never a persisted method — the value
///    stored for a Razorpay booking is `RAZORPAY`;
///  * persisted labels/icon show an online-paid booking as "Online Payment".
void main() {
  group('RazorpayOrder.fromJson', () {
    test('parses a checkout-usable order into integer paise', () {
      final order = RazorpayOrder.fromJson(const {
        'paymentId': 'p_1',
        'bookingId': 'b_1',
        'razorpayOrderId': 'order_NXc123',
        'razorpayKeyId': 'rzp_live_PublicOnly',
        'amount': 50000,
        'currency': 'INR',
        'ownerName': 'Narmitha Venkatesan',
        'parkingName': 'Pothys',
      });

      expect(order.razorpayOrderId, 'order_NXc123');
      // ₹500.00 must be 50000 integer paise, never a double.
      expect(order.amountPaise, 50000);
      expect(order.currency, 'INR');
      expect(order.isUsable, isTrue);
    });

    test('parses an amount sent as a JSON number without float drift', () {
      final order = RazorpayOrder.fromJson(const {
        'razorpayOrderId': 'order_x',
        'razorpayKeyId': 'rzp_test_abc',
        'amount': 1,
      });
      expect(order.amountPaise, 1);
      expect(order.isUsable, isTrue);
    });

    test('is not usable when the public key id is missing', () {
      final order = RazorpayOrder.fromJson(const {
        'razorpayOrderId': 'order_x',
        'amount': 50000,
      });
      expect(order.isUsable, isFalse);
    });

    test('is not usable when the order id is empty', () {
      final order = RazorpayOrder.fromJson(const {
        'razorpayOrderId': '',
        'razorpayKeyId': 'rzp_test_abc',
        'amount': 50000,
      });
      expect(order.isUsable, isFalse);
    });

    test('is not usable when the amount is missing or zero', () {
      final zero = RazorpayOrder.fromJson(const {
        'razorpayOrderId': 'order_x',
        'razorpayKeyId': 'rzp_test_abc',
        'amount': 0,
      });
      expect(zero.isUsable, isFalse);

      final missing = RazorpayOrder.fromJson(const {
        'razorpayOrderId': 'order_x',
        'razorpayKeyId': 'rzp_test_abc',
      });
      expect(missing.isUsable, isFalse);
    });

    test('defaults currency to INR for display', () {
      const json = {
        'razorpayOrderId': 'order_x',
        'razorpayKeyId': 'rzp_test_abc',
        'amount': 100,
      };
      expect(RazorpayOrder.fromJson(json).currency, 'INR');
    });
  });

  group('PaymentMethod method tokens', () {
    test('RAZORPAY is a valid persisted method, ONLINE is not', () {
      expect(PaymentMethod.isValid('RAZORPAY'), isTrue);
      expect(PaymentMethod.isValid(PaymentMethod.upi), isTrue);
      expect(PaymentMethod.isValid(PaymentMethod.cod), isTrue);
      // ONLINE only ever exists on the client; it must never be stored.
      expect(PaymentMethod.isValid(PaymentMethod.online), isFalse);
    });

    test('the production screen only offers ONLINE and COD', () {
      expect(PaymentMethod.selectable, {
        PaymentMethod.online,
        PaymentMethod.cod,
      });
      // The legacy direct-UPI deep link is out of the selectable set.
      expect(PaymentMethod.selectable.contains(PaymentMethod.upi), isFalse);
    });
  });

  group('PaymentUi method labelling', () {
    test('a Razorpay booking reads as Online Payment with a lock icon', () {
      expect(PaymentUi.methodLabel(PaymentMethod.razorpay), 'Online Payment');
      expect(PaymentUi.methodIcon(PaymentMethod.razorpay), Icons.lock_outline);
    });

    test('COD and UPI keep their original labels', () {
      expect(PaymentUi.methodLabel(PaymentMethod.cod), 'Cash on Delivery');
      expect(PaymentUi.methodLabel(PaymentMethod.upi), 'UPI');
    });
  });
}
