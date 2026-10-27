import 'package:parkshare_backend/config/config.dart';
import 'package:parkshare_backend/services/owner_payment_account_service.dart';
import 'package:parkshare_backend/services/payout_details_cipher.dart';
import 'package:test/test.dart';

import 'support/test_env.dart';

void main() {
  TestEnv.install();

  group('PayoutDetailsCipher', () {
    test('round-trips a bank account and IFSC', () {
      const account = '123456789012';
      const ifsc = 'HDFC0001234';

      final accountCipher = PayoutDetailsCipher.encrypt(account);
      final ifscCipher = PayoutDetailsCipher.encrypt(ifsc);

      expect(accountCipher, startsWith('v1.'));
      expect(accountCipher, isNot(contains(account)));
      expect(ifscCipher, isNot(contains(ifsc)));
      expect(PayoutDetailsCipher.decrypt(accountCipher), account);
      expect(PayoutDetailsCipher.decrypt(ifscCipher), ifsc);
    });

    test('uses a fresh nonce so equal values do not have equal ciphertext', () {
      final first = PayoutDetailsCipher.encrypt('123456789012');
      final second = PayoutDetailsCipher.encrypt('123456789012');
      expect(first, isNot(second));
      expect(PayoutDetailsCipher.decrypt(first), '123456789012');
      expect(PayoutDetailsCipher.decrypt(second), '123456789012');
    });

    test('rejects tampered, malformed and unknown-prefix values', () {
      final encrypted = PayoutDetailsCipher.encrypt('123456789012');
      final tampered = '${encrypted.substring(0, encrypted.length - 2)}AA';

      expect(
        () => PayoutDetailsCipher.decrypt(tampered),
        throwsA(isA<PayoutDetailsCipherException>()),
      );
      expect(
        () => PayoutDetailsCipher.decrypt('not-a-ciphertext'),
        throwsA(isA<PayoutDetailsCipherException>()),
      );
      expect(
        () => PayoutDetailsCipher.decrypt('v1.%%%'),
        throwsA(isA<PayoutDetailsCipherException>()),
      );
    });

    test('a different key cannot decrypt existing ciphertext', () {
      final encrypted = PayoutDetailsCipher.encrypt('123456789012');

      try {
        Config.applyTestOverrides({
          ...TestEnv.values,
          'OWNER_PAYOUT_ENCRYPTION_KEY':
              'TEST-ONLY-DIFFERENT-PAYOUT-KEY-000000000000000000000000000001',
        });
        expect(
          () => PayoutDetailsCipher.decrypt(encrypted),
          throwsA(isA<PayoutDetailsCipherException>()),
        );
      } finally {
        TestEnv.install();
      }
    });
  });

  group('owner-facing projection', () {
    test('never contains the encrypted destination or a full account', () {
      final projection = OwnerPaymentAccountService.maskProjection({
        'provider': 'razorpay',
        'razorpay_onboarding_status': 'PENDING',
        'razorpay_settlement_enabled': false,
        'legal_name': 'Test Owner',
        'account_type': 'INDIVIDUAL',
        'account_holder_name': 'Test Owner',
        'bank_last4': '9012',
        'payout_account_number_encrypted': PayoutDetailsCipher.encrypt(
          '123456789012',
        ),
        'payout_ifsc_encrypted': PayoutDetailsCipher.encrypt('HDFC0001234'),
        'payout_details_available': true,
        'consent_accepted_at': null,
        'updated_at': null,
      }, ownerId: '11111111-1111-1111-1111-111111111111');

      expect(projection['bankLast4'], '9012');
      expect(projection['payoutDetailsAvailable'], isTrue);
      final json = projection.toString();
      expect(json, isNot(contains('123456789012')));
      expect(json, isNot(contains('HDFC0001234')));
      expect(json, isNot(contains('payout_account_number_encrypted')));
      expect(json, isNot(contains('v1.')));
    });
  });
}
