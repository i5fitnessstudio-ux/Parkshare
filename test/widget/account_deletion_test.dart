// Widget tests for self-service account deletion:
//   * the "Delete Account" home-menu entry (both roles) and the confirm dialog,
//   * the DeleteAccountScreen password re-authentication, error copy, success
//     dialog and post-success navigation.
//
// The network is faked with a MockClient so no backend is required. Token and
// session storage are swapped for in-memory subclasses because the real ones
// talk to flutter_secure_storage (a platform channel that does not exist in a
// widget test).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:parkshare_new/app/routes.dart';
import 'package:parkshare_new/core/network/api_client.dart';
import 'package:parkshare_new/core/services/booking_service.dart';
import 'package:parkshare_new/core/services/inbox_service.dart';
import 'package:parkshare_new/core/services/parking_service.dart';
import 'package:parkshare_new/core/services/payment_service.dart';
import 'package:parkshare_new/core/services/vehicle_service.dart';
import 'package:parkshare_new/core/storage/session_storage.dart';
import 'package:parkshare_new/core/storage/token_storage.dart';
import 'package:parkshare_new/modules/account/screens/delete_account_screen.dart';
import 'package:parkshare_new/modules/auth/providers/auth_provider.dart';
import 'package:parkshare_new/modules/auth/services/auth_service.dart';
import 'package:parkshare_new/modules/booking/providers/booking_provider.dart';
import 'package:parkshare_new/modules/inbox/providers/inbox_provider.dart';
import 'package:parkshare_new/modules/owner/home/owner_dashboard_screen.dart';
import 'package:parkshare_new/modules/owner/providers/owner_dashboard_provider.dart';
import 'package:parkshare_new/modules/owner/providers/owner_parking_provider.dart';
import 'package:parkshare_new/modules/owner/providers/owner_payments_provider.dart';
import 'package:parkshare_new/modules/shared/providers/location_provider.dart';
import 'package:parkshare_new/modules/user/home/user_home_screen.dart';
import 'package:parkshare_new/modules/user/providers/user_home_tab_provider.dart';
import 'package:parkshare_new/modules/user/providers/user_map_provider.dart';
import 'package:parkshare_new/modules/vehicle/providers/vehicle_provider.dart';
import 'package:parkshare_new/shared/models/user.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class FakeTokenStorage extends TokenStorage {
  String? access;
  String? refresh;
  bool cleared = false;

  FakeTokenStorage({this.access, this.refresh});

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<String?> getAccessToken() async => access;

  @override
  Future<String?> getRefreshToken() async => refresh;

  @override
  Future<bool> hasTokens() async =>
      access != null && access!.isNotEmpty && refresh != null;

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
    cleared = true;
  }
}

class FakeSessionStorage extends SessionStorage {
  User? user;
  bool cleared = false;

  @override
  Future<void> saveSession(User user) async => this.user = user;

  @override
  Future<String?> getRole() async => user?.role;

  @override
  Future<User?> getUser() async => user;

  @override
  Future<void> clear() async {
    user = null;
    cleared = true;
  }
}

enum _DeleteMode { success, wrongPassword, network, server }

final User testUser = User(
  id: '11111111-1111-1111-1111-111111111111',
  name: 'Asha Rao',
  email: 'asha@example.com',
  role: UserRole.user,
  isActive: true,
  createdAt: DateTime(2024),
);

http.Response _envelope(
  Object? data, {
  int status = 200,
  String message = 'ok',
}) {
  return http.Response(
    jsonEncode({'success': status < 400, 'message': message, 'data': data}),
    status,
    headers: {'content-type': 'application/json'},
  );
}

/// Backend fake for the delete screen. Serves `/api/auth/me` (so the provider
/// can be signed in) and `/api/account`.
MockClient _deleteClient(_DeleteMode mode) {
  return MockClient((request) async {
    if (request.method == 'GET' && request.url.path == '/api/auth/me') {
      return _envelope(testUser.toJson());
    }
    if (request.method == 'DELETE' &&
        request.url.path == '/api/account') {
      switch (mode) {
        case _DeleteMode.success:
          return _envelope(
            null,
            message: 'Your ParkShare account has been deleted successfully.',
          );
        case _DeleteMode.wrongPassword:
          return _envelope(
            null,
            status: 403,
            message: 'Incorrect password. Please try again.',
          );
        case _DeleteMode.server:
          return _envelope(
            null,
            status: 500,
            message: 'Internal server error.',
          );
        case _DeleteMode.network:
          throw const SocketException('offline');
      }
    }
    return _envelope(<String, dynamic>{});
  });
}

/// Backend fake for the two home screens: every list endpoint answers with an
/// empty payload (services tolerate a missing key) and `/api/auth/me` signs the
/// provider in.
MockClient _homeClient() {
  return MockClient((request) async {
    if (request.method == 'GET' && request.url.path == '/api/auth/me') {
      return _envelope(testUser.toJson());
    }
    return _envelope(<String, dynamic>{});
  });
}

Future<AuthProvider> _signedInProvider(
  MockClient client,
  FakeTokenStorage tokens,
  FakeSessionStorage session,
) async {
  final auth = AuthProvider(
    authService: AuthService(ApiClient(client: client, baseUrl: 'http://test')),
    tokenStorage: tokens,
    sessionStorage: session,
  );
  await auth.restoreSession();
  return auth;
}

Widget _deleteHost(AuthProvider auth) {
  return ChangeNotifierProvider.value(
    value: auth,
    child: MaterialApp(
      home: const DeleteAccountScreen(),
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.roleSelection) {
          return MaterialPageRoute(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('ROLE_SELECTION'))),
          );
        }
        return null;
      },
    ),
  );
}

Widget _pushedDeleteHost(AuthProvider auth) {
  return ChangeNotifierProvider.value(
    value: auth,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DeleteAccountScreen(),
                ),
              ),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDelete(WidgetTester tester) async {
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------

void main() {
  group('DeleteAccountScreen — password re-authentication', () {
    testWidgets('empty password keeps the button disabled', (tester) async {
      final auth = await _signedInProvider(
        _deleteClient(_DeleteMode.success),
        FakeTokenStorage(access: 'a', refresh: 'r'),
        FakeSessionStorage(),
      );
      await tester.pumpWidget(_deleteHost(auth));
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Delete Account Permanently'),
      );
      expect(button.onPressed, isNull, reason: 'nothing to submit yet');

      await tester.enterText(find.byType(TextFormField), 'hunter2');
      await tester.pump();
      final enabled = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Delete Account Permanently'),
      );
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets('the eye toggles password visibility', (tester) async {
      final auth = await _signedInProvider(
        _deleteClient(_DeleteMode.success),
        FakeTokenStorage(access: 'a', refresh: 'r'),
        FakeSessionStorage(),
      );
      await tester.pumpWidget(_deleteHost(auth));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      expect(find.byTooltip('Show password'), findsOneWidget);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();

      final revealed = tester.widget<TextField>(find.byType(TextField));
      expect(revealed.obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('a wrong password shows the exact copy and keeps the session',
        (tester) async {
      final tokens = FakeTokenStorage(access: 'a', refresh: 'r');
      final session = FakeSessionStorage();
      final auth = await _signedInProvider(
        _deleteClient(_DeleteMode.wrongPassword),
        tokens,
        session,
      );
      await tester.pumpWidget(_deleteHost(auth));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'wrong-pass');
      await tester.pump();
      await tester.tap(find.text('Delete Account Permanently'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect password. Please try again.'), findsOneWidget);
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
      expect(session.cleared, isFalse, reason: 'the account was not deleted');

      // Let the snackbar's auto-dismiss timer elapse so it is not "pending".
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a network failure shows the connectivity copy', (tester) async {
      final auth = await _signedInProvider(
        _deleteClient(_DeleteMode.network),
        FakeTokenStorage(access: 'a', refresh: 'r'),
        FakeSessionStorage(),
      );
      await tester.pumpWidget(_deleteHost(auth));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'hunter2');
      await tester.pump();
      await tester.tap(find.text('Delete Account Permanently'));
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to connect to the server. Please try again.'),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a server failure shows the generic copy (no raw error)',
        (tester) async {
      final auth = await _signedInProvider(
        _deleteClient(_DeleteMode.server),
        FakeTokenStorage(access: 'a', refresh: 'r'),
        FakeSessionStorage(),
      );
      await tester.pumpWidget(_deleteHost(auth));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'hunter2');
      await tester.pump();
      await tester.tap(find.text('Delete Account Permanently'));
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to delete your account right now. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.textContaining('500'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('success clears the session and returns to role selection',
        (tester) async {
      final tokens = FakeTokenStorage(access: 'a', refresh: 'r');
      final session = FakeSessionStorage();
      final auth = await _signedInProvider(
        _deleteClient(_DeleteMode.success),
        tokens,
        session,
      );
      await tester.pumpWidget(_deleteHost(auth));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'hunter2');
      await tester.pump();
      await tester.tap(find.text('Delete Account Permanently'));
      await tester.pumpAndSettle();

      expect(
        find.text('Your ParkShare account has been deleted successfully.'),
        findsOneWidget,
      );
      expect(tokens.cleared, isTrue, reason: 'tokens removed');
      expect(session.cleared, isTrue, reason: 'cached session removed');

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('ROLE_SELECTION'), findsOneWidget);
      expect(find.byType(DeleteAccountScreen), findsNothing);
    });

    testWidgets('back asks to confirm before leaving', (tester) async {
      final auth = await _signedInProvider(
        _deleteClient(_DeleteMode.success),
        FakeTokenStorage(access: 'a', refresh: 'r'),
        FakeSessionStorage(),
      );
      await tester.pumpWidget(_pushedDeleteHost(auth));
      await tester.pumpAndSettle();
      await _openDelete(tester);
      expect(find.byType(DeleteAccountScreen), findsOneWidget);

      // Back -> confirm dialog, "Stay" keeps the user on the screen.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Cancel account deletion?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteAccountScreen), findsOneWidget);

      // Back -> confirm dialog, "Leave" pops the screen.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteAccountScreen), findsNothing);
      expect(find.text('OPEN'), findsOneWidget);
    });
  });

  group('Home menu — Delete Account sits below Logout', () {
    testWidgets('vehicle-user home shows the entry and confirms once',
        (tester) async {
      final auth = await _signedInProvider(
        _homeClient(),
        FakeTokenStorage(access: 'a', refresh: 'r'),
        FakeSessionStorage(),
      );
      final api = ApiClient(client: _homeClient(), baseUrl: 'http://test');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: auth),
            ChangeNotifierProvider(
              create: (_) => VehicleProvider(service: VehicleService(client: api)),
            ),
            ChangeNotifierProvider(
              create: (_) => BookingProvider(service: BookingService(client: api)),
            ),
            ChangeNotifierProvider(
              create: (_) => InboxProvider(service: InboxService(client: api)),
            ),
            ChangeNotifierProvider(create: (_) => LocationProvider()),
            ChangeNotifierProvider(create: (_) => UserHomeTabProvider()),
            ChangeNotifierProvider(
              create: (_) => UserMapProvider(
                parkingService: ParkingService(client: api),
              ),
            ),
          ],
          child: MaterialApp(
            home: const UserHomeScreen(),
            onGenerateRoute: (settings) {
              if (settings.name == AppRoutes.deleteAccount) {
                return MaterialPageRoute(
                  builder: (_) => const DeleteAccountScreen(),
                );
              }
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Logout'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Delete Account')).dy,
        greaterThan(tester.getTopLeft(find.text('Logout')).dy),
        reason: 'Delete Account is directly below Logout',
      );

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Account?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
    });

    testWidgets('owner home shows the entry below Logout', (tester) async {
      final owner = User(
        id: testUser.id,
        name: 'Owner One',
        email: 'owner@example.com',
        role: UserRole.owner,
        isActive: true,
        createdAt: DateTime(2024),
      );
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/api/auth/me') {
          return _envelope(owner.toJson());
        }
        return _envelope(<String, dynamic>{});
      });
      final auth = await _signedInProvider(
        client,
        FakeTokenStorage(access: 'a', refresh: 'r'),
        FakeSessionStorage(),
      );
      final api = ApiClient(client: client, baseUrl: 'http://test');

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
          child: MaterialApp(
            home: const OwnerDashboardScreen(),
            onGenerateRoute: (settings) {
              if (settings.name == AppRoutes.deleteAccount) {
                return MaterialPageRoute(
                  builder: (_) => const DeleteAccountScreen(),
                );
              }
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Logout'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Delete Account')).dy,
        greaterThan(tester.getTopLeft(find.text('Logout')).dy),
      );

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Account?'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
    });
  });
}
