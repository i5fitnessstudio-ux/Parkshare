// Widget tests for the owner bottom navigation after "Payments & Settlements"
// was moved out of the three-dot overflow menu and into the bottom navigation.
//
// Covers:
//  * the five destinations, in order, with the short "Payments" label;
//  * tapping Payments shows the existing Payments & Settlements surface;
//  * the overflow menu no longer offers Payments & Settlements while Refresh,
//    Logout and Delete Account stay put.
//
// The network is faked with a MockClient so no backend is required.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parkshare_new/core/network/api_client.dart';
import 'package:parkshare_new/core/services/booking_service.dart';
import 'package:parkshare_new/core/services/inbox_service.dart';
import 'package:parkshare_new/core/services/parking_service.dart';
import 'package:parkshare_new/core/services/payment_service.dart';
import 'package:parkshare_new/core/storage/session_storage.dart';
import 'package:parkshare_new/core/storage/token_storage.dart';
import 'package:parkshare_new/modules/auth/providers/auth_provider.dart';
import 'package:parkshare_new/modules/auth/services/auth_service.dart';
import 'package:parkshare_new/modules/booking/providers/booking_provider.dart';
import 'package:parkshare_new/modules/inbox/providers/inbox_provider.dart';
import 'package:parkshare_new/modules/owner/home/owner_dashboard_screen.dart';
import 'package:parkshare_new/modules/owner/payments/payments_settlements_screen.dart';
import 'package:parkshare_new/modules/owner/providers/owner_dashboard_provider.dart';
import 'package:parkshare_new/modules/owner/providers/owner_parking_provider.dart';
import 'package:parkshare_new/modules/owner/providers/owner_payments_provider.dart';
import 'package:parkshare_new/shared/models/user.dart';
import 'package:provider/provider.dart';

class _FakeTokenStorage extends TokenStorage {
  String? access = 'a';
  String? refresh = 'r';

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

MockClient _client() => MockClient((request) async {
  if (request.method == 'GET' && request.url.path == '/api/auth/me') {
    return _envelope(_owner.toJson());
  }
  return _envelope(<String, dynamic>{});
});

Future<void> _pumpOwnerHome(WidgetTester tester) async {
  // Phone-sized, compact window -> bottom NavigationBar (not the rail).
  // Wide enough that the flutter-test Ahem font does not force unrelated
  // dashboard cards to overflow; still under the 600dp compact breakpoint.
  tester.view.physicalSize = const Size(560, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final api = ApiClient(client: _client(), baseUrl: 'http://test');
  final auth = AuthProvider(
    authService: AuthService(api),
    tokenStorage: _FakeTokenStorage(),
    sessionStorage: _FakeSessionStorage(),
  );
  await auth.restoreSession();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(
          create: (_) => OwnerDashboardProvider(
            parkingService: ParkingService(client: api),
            bookingService: BookingService(client: api),
            paymentService: PaymentService(client: api),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => OwnerParkingProvider(
            service: ParkingService(client: api),
            client: api,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => BookingProvider(service: BookingService(client: api)),
        ),
        ChangeNotifierProvider(
          create: (_) => InboxProvider(service: InboxService(client: api)),
        ),
        ChangeNotifierProvider(
          create: (_) => OwnerPaymentsProvider(
            paymentService: PaymentService(client: api),
          ),
        ),
      ],
      child: const MaterialApp(home: OwnerDashboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('owner bottom navigation has five destinations in order', (
    tester,
  ) async {
    await _pumpOwnerHome(tester);

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    final labels = bar.destinations
        .cast<NavigationDestination>()
        .map((d) => d.label)
        .toList();

    expect(labels, ['Dashboard', 'Parkings', 'Bookings', 'Payments', 'Inbox']);
  });

  testWidgets('tapping Payments opens the Payments & Settlements surface', (
    tester,
  ) async {
    await _pumpOwnerHome(tester);

    await tester.tap(find.text('Payments'));
    await tester.pumpAndSettle();

    // The surrounding scaffold shows the screen title for this tab and the
    // embedded surface renders its first card.
    expect(find.text('Payments & Settlements'), findsOneWidget);
    expect(find.byType(PaymentsSettlementsScreen), findsOneWidget);
    expect(find.text('Payment Account'), findsOneWidget);
    expect(find.text('Not Completed'), findsOneWidget);
  });

  testWidgets('Payments & Settlements is gone from the overflow menu', (
    tester,
  ) async {
    await _pumpOwnerHome(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Payments & Settlements'), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    expect(find.text('Delete Account'), findsOneWidget);
  });
}
