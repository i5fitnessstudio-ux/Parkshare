// Regression tests for audit C-01 (UPI must never be self-verified) and the
// COD state machine that must keep working exactly as specified:
//
//   COD_PENDING -> owner confirms cash -> backend verifies owner ownership
//   -> COD_CONFIRMED -> booking CONFIRMED -> earnings increase (once)
//
// These are pure domain-invariant tests: they need no database, which is what
// makes them cheap enough to run on every commit.
import 'package:parkshare_backend/models/booking.dart';
import 'package:parkshare_backend/services/payment_service.dart';
import 'package:test/test.dart';

void main() {
  group('C-01: an unverified UPI claim is never a paid status', () {
    test('UPI_PENDING_VERIFICATION is not in PaymentStatus.paid', () {
      expect(
        PaymentStatus.paid,
        isNot(contains(PaymentStatus.upiPendingVerification)),
        reason:
            'If this fails, owner earnings would include money the backend '
            'never verified.',
      );
    });

    test('UPI_PENDING_VERIFICATION is an "awaiting verification" status', () {
      expect(
        PaymentStatus.awaiting,
        contains(PaymentStatus.upiPendingVerification),
      );
      expect(
        PaymentStatus.isUnverified(PaymentStatus.upiPendingVerification),
        isTrue,
      );
    });

    test('UPI_PENDING_VERIFICATION does not occupy the parking slot', () {
      expect(
        occupyingStatusList,
        isNot(contains(PaymentStatus.upiPendingVerification)),
        reason:
            'An unpaid UPI claim must leave the space bookable, exactly like '
            'COD_PENDING.',
      );
      expect(BookingStatus.occupying, isNot(contains(PaymentStatus.upiPendingVerification)));
    });

    test('only SUCCESS and COD_CONFIRMED count as earnings', () {
      expect(PaymentStatus.paid, {PaymentStatus.success, PaymentStatus.codConfirmed});
    });

    test('isUnverified is true for every pending/cash state and false for paid',
        () {
      for (final status in PaymentStatus.awaiting) {
        expect(PaymentStatus.isUnverified(status), isTrue, reason: status);
      }
      for (final status in PaymentStatus.paid) {
        expect(PaymentStatus.isUnverified(status), isFalse, reason: status);
      }
      expect(PaymentStatus.isUnverified(PaymentStatus.failed), isFalse);
      expect(PaymentStatus.isUnverified(PaymentStatus.refunded), isFalse);
    });

    test('isUnverified is case tolerant (defensive against raw DB strings)', () {
      expect(PaymentStatus.isUnverified('upi_pending_verification'), isTrue);
      expect(PaymentStatus.isUnverified('cod_pending'), isTrue);
    });
  });

  group('COD state machine invariants are preserved', () {
    test('COD_PENDING is unverified and does not hold the slot', () {
      expect(PaymentStatus.awaiting, contains(PaymentStatus.codPending));
      expect(PaymentStatus.paid, isNot(contains(PaymentStatus.codPending)));
      expect(occupyingStatusList, isNot(contains(PaymentStatus.codPending)));
    });

    test('COD_CONFIRMED is a paid status', () {
      expect(PaymentStatus.paid, contains(PaymentStatus.codConfirmed));
    });

    test('only UPI and COD payment methods exist', () {
      expect(PaymentMethod.all, {PaymentMethod.upi, PaymentMethod.cod});
    });
  });

  group('User-facing UPI message never claims the money arrived', () {
    test('mentions that the owner verifies it', () {
      final text = kUpiUnverifiedMessage.toLowerCase();
      expect(text, contains('owner'));
      expect(text, contains('check'));
      expect(text, contains('confirm'));
    });

    test('never contains success / verified / paid language', () {
      final text = kUpiUnverifiedMessage.toLowerCase();
      for (final forbidden in [
        'payment successful',
        'payment success',
        'successfully paid',
        'payment verified',
        'verified payment',
        'paid successfully',
        'transaction id',
        'txn id',
      ]) {
        expect(text, isNot(contains(forbidden)));
      }
    });

    test('explicitly says it cannot be verified yet', () {
      expect(
        kUpiUnverifiedMessage.toLowerCase(),
        contains('cannot be verified'),
      );
    });
  });

  group('bookingCoreJson never launders a pending claim as paid', () {
    test('exposes the raw paymentStatus and the owner-settlement timestamp', () {
      final json = bookingCoreJson(<String, dynamic>{
        'id': 'b1',
        'parking_id': 'p1',
        'user_id': 'u1',
        'owner_id': 'o1',
        'payment_status': PaymentStatus.upiPendingVerification,
        'status': BookingStatus.paymentPending,
      });

      expect(json['paymentStatus'], PaymentStatus.upiPendingVerification);
      expect(json['upiVerifiedAt'], isNull);
      expect(json['upiVerifiedBy'], isNull);
      // Nothing invented: no transaction id when the client sent none.
      expect(json['upiTransactionId'], isNull);
      expect(json['paymentReference'], isNull);
    });

    test('the owner settlement timestamp is serialised when present', () {
      final json = bookingCoreJson(<String, dynamic>{
        'id': 'b1',
        'payment_status': PaymentStatus.success,
        'status': BookingStatus.confirmed,
        'upi_verified_at': DateTime.utc(2026, 1, 2, 3, 4, 5),
        'upi_verified_by': 'owner-1',
      });

      expect(json['upiVerifiedAt'], '2026-01-02T03:04:05.000Z');
      expect(json['upiVerifiedBy'], 'owner-1');
    });
  });
}
