import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/core/services/payment_service.dart';
import 'package:parkshare_new/modules/owner/providers/owner_payments_provider.dart';
import 'package:parkshare_new/shared/models/owner_payment_info.dart';

class _FakeOwnerPaymentsApi extends PaymentService {
  _FakeOwnerPaymentsApi({this.completer});

  final Completer<void>? completer;

  @override
  Future<OwnerPaymentAccount> fetchOwnerPaymentAccount({
    required String token,
  }) async {
    if (completer != null) await completer!.future;
    return const OwnerPaymentAccount(
      ownerId: 'owner-a',
      setupCompleted: true,
      onboardingStatus: OwnerPaymentAccount.pending,
      bankLast4: '1234',
    );
  }

  @override
  Future<OwnerEarningsSummary> fetchOwnerEarnings({
    required String token,
  }) async {
    if (completer != null) await completer!.future;
    return const OwnerEarningsSummary(
      ownerId: 'owner-a',
      totalEarnings: 100,
      pendingSettlementPaise: 9000,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reset clears the previous account and earnings', () async {
    final provider = OwnerPaymentsProvider(
      paymentService: _FakeOwnerPaymentsApi(),
    );

    await provider.load(token: 'token');
    expect(provider.account, isNotNull);
    expect(provider.earnings, isNotNull);
    expect(provider.pendingSettlementPaise, 9000);

    provider.resetForAccountSwitch();

    expect(provider.account, isNull);
    expect(provider.earnings, isNull);
    expect(provider.pendingSettlementPaise, 0);
    expect(provider.loading, isFalse);
    expect(provider.error, isNull);
  });

  test(
    'an in-flight load for the previous account cannot repopulate state',
    () async {
      final gate = Completer<void>();
      final provider = OwnerPaymentsProvider(
        paymentService: _FakeOwnerPaymentsApi(completer: gate),
      );

      final loading = provider.load(token: 'token');
      await Future<void>.delayed(Duration.zero);
      expect(provider.loading, isTrue);

      provider.resetForAccountSwitch();
      gate.complete();
      await loading;

      expect(provider.account, isNull);
      expect(provider.earnings, isNull);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    },
  );
}
