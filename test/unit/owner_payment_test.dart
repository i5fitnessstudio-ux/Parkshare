import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/shared/models/booking.dart';
import 'package:parkshare_new/shared/models/owner_payment_info.dart';
import 'package:parkshare_new/shared/utils/owner_payment_validation.dart';

/// Locks in the owner "Payments & Settlements" contract:
///  * the setup validators reject bad bank input with the right message;
///  * the owner-facing payment-account model is masked and NEVER reads a full
///    account number even if one were ever sent;
///  * a Razorpay booking is not a legacy direct-UPI booking, so the owner UI can
///    never offer a manual "Verify UPI" or expose the owner's UPI id.
void main() {
  group('OwnerPaymentValidation', () {
    test('accepts a complete, well-formed setup', () {
      expect(OwnerPaymentValidation.validateLegalName('Poorani S'), isNull);
      expect(OwnerPaymentValidation.validateAccountType('INDIVIDUAL'), isNull);
      expect(OwnerPaymentValidation.validateMobile('9876543210'), isNull);
      expect(
        OwnerPaymentValidation.validateEmail('poorani@example.com'),
        isNull,
      );
      expect(
        OwnerPaymentValidation.validateAccountHolderName('Poorani S'),
        isNull,
      );
      expect(
        OwnerPaymentValidation.validateAccountNumber('123456789012'),
        isNull,
      );
      expect(
        OwnerPaymentValidation.validateConfirmAccountNumber(
          '123456789012',
          '123456789012',
        ),
        isNull,
      );
      expect(OwnerPaymentValidation.validateIfsc('HDFC0001234'), isNull);
      expect(OwnerPaymentValidation.validateConsent(true), isNull);
    });

    test('rejects a bank account confirmation mismatch', () {
      expect(
        OwnerPaymentValidation.validateConfirmAccountNumber(
          '999999999999',
          '123456789012',
        ),
        contains('do not match'),
      );
    });

    test('rejects an invalid IFSC', () {
      expect(
        OwnerPaymentValidation.validateIfsc('HDFC1234567'),
        contains('IFSC'),
      );
      expect(
        OwnerPaymentValidation.validateIfsc('HDF0001234'),
        contains('IFSC'),
      );
    });

    test('rejects a too-short account number', () {
      expect(
        OwnerPaymentValidation.validateAccountNumber('12345'),
        contains('account number'),
      );
    });

    test('rejects an invalid email', () {
      expect(
        OwnerPaymentValidation.validateEmail('not-an-email'),
        contains('email'),
      );
    });

    test('rejects an invalid mobile number', () {
      expect(
        OwnerPaymentValidation.validateMobile('12345'),
        contains('mobile'),
      );
    });

    test('requires consent', () {
      expect(
        OwnerPaymentValidation.validateConsent(false),
        contains('settlement terms'),
      );
    });

    test('extracts the last four digits', () {
      expect(OwnerPaymentValidation.last4('123456789012'), '9012');
      expect(OwnerPaymentValidation.last4('1234'), '1234');
    });
  });

  group('OwnerPaymentAccount.fromJson is masked', () {
    test('reads only the last four digits', () {
      final account = OwnerPaymentAccount.fromJson(const {
        'ownerId': 'o_1',
        'provider': 'RAZORPAY',
        'onboardingStatus': 'PENDING',
        'settlementEnabled': false,
        'setupCompleted': true,
        'accountHolderName': 'Poorani S',
        'bankLast4': '9012',
      });

      expect(account.bankLast4, '9012');
      expect(account.maskedBank, '•••• 9012');
      expect(account.isPending, isTrue);
      expect(account.isNotStarted, isFalse);
      // A saved-but-unverified account shows Pending and settlement stays
      // NOT enabled — the app must never claim Verified/Enabled on its own.
      expect(account.statusLabel, 'Pending');
      expect(account.settlementEnabled, isFalse);
      expect(account.settlementLabel, 'Not Enabled');
    });

    test('ignores a full account number if one is ever sent', () {
      final account = OwnerPaymentAccount.fromJson(const {
        'ownerId': 'o_1',
        'bankAccountNumber': '123456789012',
        'ifscCode': 'HDFC0001234',
      });

      // No whitelisted bankLast4 → nothing is displayed, and there is no getter
      // that could surface the raw account number.
      expect(account.bankLast4, '');
      expect(account.maskedBank, isNull);
    });

    test('a missing account is NOT_STARTED', () {
      final account = OwnerPaymentAccount.fromJson(const {});
      expect(account.isNotStarted, isTrue);
      expect(account.setupCompleted, isFalse);
      expect(account.onboardingStatus, OwnerPaymentAccount.notStarted);
    });
  });

  group('OwnerEarningsSummary settlement fields', () {
    test('parses settlement totals and entries', () {
      final summary = OwnerEarningsSummary.fromJson(const {
        'ownerId': 'o_1',
        'totalEarnings': 1200,
        'pendingSettlementPaise': 95000,
        'settledPaise': 0,
        'transferCount': 2,
        'settlementEntries': [
          {
            'bookingId': 'b_1',
            'parkingName': 'Sunrise',
            'grossAmountPaise': 100000,
            'platformFeePaise': 5000,
            'ownerAmountPaise': 95000,
            'settlementStatus': 'PENDING',
            'paymentStatus': 'SUCCESS',
          },
        ],
      });

      expect(summary.pendingSettlementPaise, 95000);
      expect(summary.settledPaise, 0);
      expect(summary.transferCount, 2);
      expect(summary.settlementEntries, hasLength(1));
      expect(summary.settlementEntries.first.isSettled, isFalse);
      expect(summary.settlementEntries.first.ownerAmountPaise, 95000);
    });
  });

  group('Booking legacy-UPI vs Razorpay gating', () {
    Map<String, dynamic> base() => {
      'bookingId': 'b_1',
      'parkingId': 'p_1',
      'userId': 'u_1',
      'ownerId': 'o_1',
      'vehicleId': 'v_1',
      'amount': 500,
      'status': BookingStatus.confirmed,
      'createdAt': '2024-01-01T00:00:00.000Z',
      'updatedAt': '2024-01-01T00:00:00.000Z',
      'owner': {'id': 'o_1', 'name': 'Owner A', 'upiId': 'owner@upi'},
    };

    test('a Razorpay booking is never a legacy direct-UPI booking', () {
      final booking = Booking.fromJson({
        ...base(),
        'paymentMethod': 'RAZORPAY',
        'paymentStatus': 'SUCCESS',
      });

      expect(booking.isRazorpay, isTrue);
      expect(booking.isLegacyDirectUpi, isFalse);
      // Even though the owner has a UPI id, a Razorpay booking must not expose
      // it in the owner UI.
      expect(booking.showsOwnerUpiId, isFalse);
    });

    test('a pending direct-UPI booking is a legacy booking', () {
      final booking = Booking.fromJson({
        ...base(),
        'paymentMethod': 'UPI',
        'paymentStatus': 'UPI_PENDING_VERIFICATION',
      });

      expect(booking.isLegacyDirectUpi, isTrue);
      expect(booking.showsOwnerUpiId, isTrue);
    });

    test('a paid direct-UPI booking is no longer pending verification', () {
      final booking = Booking.fromJson({
        ...base(),
        'paymentMethod': 'UPI',
        'paymentStatus': 'SUCCESS',
      });
      expect(booking.isLegacyDirectUpi, isFalse);
    });

    test('COD is unaffected', () {
      final booking = Booking.fromJson({
        ...base(),
        'paymentMethod': 'COD',
        'paymentStatus': 'COD_PENDING',
        'status': BookingStatus.codPending,
      });
      expect(booking.isCod, isTrue);
      expect(booking.isLegacyDirectUpi, isFalse);
      expect(booking.isCodPending, isTrue);
    });
  });
}
