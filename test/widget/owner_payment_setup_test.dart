// Widget tests for the owner "Set Up Payment Account" form.
//
// Covers the client-side guarantees that matter for money safety:
//  * a mismatched confirmation blocks the submit and sends NOTHING;
//  * a valid submit sends exactly one request and the provider then holds the
//    masked account (last-4 only) the backend returned.
//
// The backend re-validates everything; these tests only prove the app does not
// fire a doomed request and does not invent a payout state.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parkshare_new/core/network/api_client.dart';
import 'package:parkshare_new/core/services/payment_service.dart';
import 'package:parkshare_new/core/storage/session_storage.dart';
import 'package:parkshare_new/core/storage/token_storage.dart';
import 'package:parkshare_new/modules/auth/providers/auth_provider.dart';
import 'package:parkshare_new/modules/auth/services/auth_service.dart';
import 'package:parkshare_new/modules/owner/payments/owner_payment_setup_screen.dart';
import 'package:parkshare_new/modules/owner/providers/owner_payments_provider.dart';
import 'package:parkshare_new/shared/models/user.dart';
import 'package:provider/provider.dart';

class _FakeTokenStorage extends TokenStorage {
  String? access = 'access-token';
  String? refresh = 'refresh-token';

  @override
  Future<String?> getAccessToken() async => access;

  @override
  Future<String?> getRefreshToken() async => refresh;

  @override
  Future<bool> hasTokens() async => access != null && refresh != null;

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }
}

class _FakeSessionStorage extends SessionStorage {
  User? user;
  @override
  Future<User?> getUser() async => user;
  @override
  Future<String?> getRole() async => user?.role;
  @override
  Future<void> saveSession(User user) async => this.user = user;
  @override
  Future<void> clear() async => user = null;
}

http.Response _envelope(Object? data, {int status = 200}) => http.Response(
  jsonEncode({'success': status < 400, 'message': 'ok', 'data': data}),
  status,
  headers: {'content-type': 'application/json'},
);

final _owner = User(
  id: '11111111-1111-1111-1111-111111111111',
  name: 'Owner One',
  email: 'owner@example.com',
  phone: '9876543210',
  role: UserRole.owner,
  isActive: true,
  createdAt: DateTime(2024),
);

void main() {
  late List<String> calls;

  MockClient client() {
    calls = [];
    return MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      if (request.method == 'GET' && request.url.path == '/api/auth/me') {
        return _envelope(_owner.toJson());
      }
      if (request.url.path == '/api/payments/owner/payment-account' &&
          request.method == 'PUT') {
        return _envelope(const {
          'ownerId': '11111111-1111-1111-1111-111111111111',
          'provider': 'RAZORPAY',
          'onboardingStatus': 'PENDING',
          'settlementEnabled': false,
          'setupCompleted': true,
          'accountHolderName': 'Poorani S',
          'bankLast4': '9012',
        });
      }
      return _envelope(<String, dynamic>{});
    });
  }

  Future<(AuthProvider, OwnerPaymentsProvider)> pump(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mock = client();
    final api = ApiClient(client: mock, baseUrl: 'http://test');
    final auth = AuthProvider(
      authService: AuthService(api),
      tokenStorage: _FakeTokenStorage(),
      sessionStorage: _FakeSessionStorage(),
    );
    await auth.restoreSession();
    final payments = OwnerPaymentsProvider(
      paymentService: PaymentService(client: api),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: payments),
        ],
        child: const MaterialApp(home: OwnerPaymentSetupScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (auth, payments);
  }

  Future<void> fillValid(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Poorani S'); // legal name
    await tester.enterText(fields.at(1), '9876543210'); // mobile
    await tester.enterText(fields.at(2), 'poorani@example.com'); // email
    await tester.enterText(fields.at(3), 'Poorani S'); // account holder
    await tester.enterText(fields.at(4), '123456789012'); // account number
    await tester.enterText(fields.at(5), '123456789012'); // confirm
    await tester.enterText(fields.at(6), 'HDFC0001234'); // ifsc
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
  }

  testWidgets('a mismatched confirmation blocks the submit and sends nothing', (
    tester,
  ) async {
    await pump(tester);
    await fillValid(tester);
    // Break the confirmation on purpose.
    await tester.enterText(find.byType(TextFormField).at(5), '999999999999');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Payment Account'));
    await tester.pumpAndSettle();

    expect(find.text('Bank account numbers do not match.'), findsOneWidget);
    expect(
      calls.any((c) => c.contains('payment-account') && c.startsWith('PUT')),
      isFalse,
    );
  });

  testWidgets('a valid setup sends one request and stores the masked account', (
    tester,
  ) async {
    final (_, payments) = await pump(tester);
    await fillValid(tester);

    await tester.tap(find.text('Save Payment Account'));
    await tester.pumpAndSettle();

    final puts = calls
        .where((c) => c.startsWith('PUT') && c.contains('payment-account'))
        .length;
    expect(puts, 1);
    // The provider now holds the backend's masked projection.
    expect(payments.account, isNotNull);
    // A valid save lands in PENDING — never VERIFIED, never settled locally.
    expect(payments.account!.isPending, isTrue);
    expect(payments.account!.isVerified, isFalse);
    // Only the masked last-4 is retained; the full number is gone.
    expect(payments.account!.bankLast4, '9012');
    expect(payments.account!.maskedBank, '•••• 9012');
    expect(payments.account!.bankLast4, isNot('123456789012'));
    expect(payments.account!.settlementEnabled, isFalse);
    expect(payments.settlementEnabled, isFalse);
  });
}
