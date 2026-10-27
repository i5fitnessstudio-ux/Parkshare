// Widget tests for the owner "Payments & Settlements" surface.
//
// Covers the entry point the owner sees on first visit:
//  * the screen opens with the "Not Completed" payment-account state;
//  * the "Set Up Payment Account" action opens the Bank Details form.
//
// The backend re-validates everything; these tests only prove the frontend
// presents the correct initial state and routes the owner into the setup form.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parkshare_new/app/routes.dart';
import 'package:parkshare_new/core/network/api_client.dart';
import 'package:parkshare_new/core/services/payment_service.dart';
import 'package:parkshare_new/core/storage/session_storage.dart';
import 'package:parkshare_new/core/storage/token_storage.dart';
import 'package:parkshare_new/modules/auth/providers/auth_provider.dart';
import 'package:parkshare_new/modules/auth/services/auth_service.dart';
import 'package:parkshare_new/modules/owner/payments/owner_payment_setup_screen.dart';
import 'package:parkshare_new/modules/owner/payments/payments_settlements_screen.dart';
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
  // An owner with no payment account yet: the account endpoint returns an empty
  // body, which the model reads as NOT_STARTED.
  MockClient notStartedClient() => MockClient((request) async {
    if (request.method == 'GET' && request.url.path == '/api/auth/me') {
      return _envelope(_owner.toJson());
    }
    return _envelope(<String, dynamic>{});
  });

  // An owner who has already saved bank details: backend reports PENDING
  // onboarding, settlement NOT enabled, and only the last four digits.
  MockClient savedClient() => MockClient((request) async {
    if (request.method == 'GET' && request.url.path == '/api/auth/me') {
      return _envelope(_owner.toJson());
    }
    if (request.method == 'GET' &&
        request.url.path == '/api/payments/owner/payment-account') {
      return _envelope({
        'ownerId': _owner.id,
        'provider': 'RAZORPAY',
        'onboardingStatus': 'PENDING',
        'settlementEnabled': false,
        'setupCompleted': true,
        'accountHolderName': 'Owner One',
        'accountType': 'INDIVIDUAL',
        'bankLast4': '4582',
      });
    }
    // Earnings: one payout still PENDING, one already SETTLED (as an admin's
    // manual settlement would leave it). Payment is PAID in both cases.
    if (request.method == 'GET' &&
        request.url.path == '/api/payments/owner/earnings') {
      return _envelope({
        'ownerId': _owner.id,
        'totalEarnings': 1200,
        'pendingSettlementPaise': 95000,
        'settledPaise': 25000,
        'transferCount': 2,
        'source': 'server',
        'settlementEntries': [
          {
            'bookingId': 'bbbbbbbb-1111-2222-3333-444444444444',
            'parkingName': 'Sunrise Residency',
            'grossAmountPaise': 100000,
            'platformFeePaise': 5000,
            'ownerAmountPaise': 95000,
            'settlementStatus': 'PENDING',
            'paymentStatus': 'SUCCESS',
          },
          {
            'bookingId': 'cccccccc-1111-2222-3333-444444444444',
            'parkingName': 'Lake View',
            'grossAmountPaise': 30000,
            'platformFeePaise': 5000,
            'ownerAmountPaise': 25000,
            'settlementStatus': 'SETTLED',
            'paymentStatus': 'SUCCESS',
          },
        ],
      });
    }
    return _envelope(<String, dynamic>{});
  });

  Future<OwnerPaymentsProvider> pumpScreen(
    WidgetTester tester, {
    http.Client? client,
  }) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = ApiClient(
      client: client ?? notStartedClient(),
      baseUrl: 'http://test',
    );
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
        child: MaterialApp(
          routes: {
            AppRoutes.ownerPaymentSetup: (_) => const OwnerPaymentSetupScreen(),
          },
          home: const PaymentsSettlementsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return payments;
  }

  testWidgets('Payments & Settlements opens with the Not Completed state', (
    tester,
  ) async {
    final payments = await pumpScreen(tester);

    expect(find.text('Payments & Settlements'), findsOneWidget);
    expect(find.text('Payment Account'), findsOneWidget);
    expect(find.text('Not Completed'), findsOneWidget);
    expect(
      find.text(
        'Complete your payment account setup to receive ParkShare settlements.',
      ),
      findsOneWidget,
    );
    expect(find.text('Set Up Payment Account'), findsOneWidget);

    // Initial state: nothing set up, nothing settled.
    expect(payments.account?.isNotStarted, isTrue);
    expect(payments.hasSetup, isFalse);
    expect(payments.settlementEnabled, isFalse);
  });

  testWidgets('Set Up Payment Account opens the Bank Details form', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Set Up Payment Account'));
    await tester.pumpAndSettle();

    // The Bank Details form is now on screen.
    expect(find.byType(OwnerPaymentSetupScreen), findsOneWidget);
    expect(find.text('Bank Details'), findsOneWidget);
    expect(find.text('Save Payment Account'), findsOneWidget);
  });

  testWidgets(
    'a saved account reloads from the backend as Pending / Not Enabled',
    (tester) async {
      final payments = await pumpScreen(tester, client: savedClient());

      // Setup is PENDING and settlement is NOT enabled — never Verified/Enabled.
      expect(payments.account?.onboardingStatus, 'PENDING');
      expect(payments.settlementEnabled, isFalse);

      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Not Enabled'), findsOneWidget);
      expect(find.text('•••• 4582'), findsOneWidget);
      expect(find.text('Owner One'), findsOneWidget);

      expect(find.text('Verified'), findsNothing);
      expect(find.text('Enabled'), findsNothing);
      expect(find.text('Not Completed'), findsNothing);
    },
  );

  testWidgets(
    'owner sees Payment/Settlement status per earning and cannot settle',
    (tester) async {
      await pumpScreen(tester, client: savedClient());

      // Per-earning: Payment is PAID while settlement is independently
      // PENDING or SETTLED.
      expect(find.textContaining('Payment: PAID'), findsNWidgets(2));
      expect(find.textContaining('Settlement: PENDING'), findsOneWidget);
      expect(find.textContaining('Settlement: SETTLED'), findsOneWidget);

      // Server-computed totals.
      expect(find.text('Pending Settlement'), findsOneWidget);
      expect(find.text('Settled Amount'), findsOneWidget);

      // The owner must have NO control to mark their own settlement complete.
      for (final label in [
        'Mark Settled',
        'Mark as Settled',
        'Settle Now',
        'Confirm Settlement',
        'Mark Settlement Complete',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    },
  );
}
