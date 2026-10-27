// ParkShare startup-flow smoke tests.
//
// The startup flow is intentionally session-independent and deterministic:
//
//   BlueSplashScreen (1.5 s, same blue as SplashScreen, no white logo page)
//     -> SplashScreen (the single decision point)
//     -> OnboardingIntroScreen (3 pages)
//     -> RoleSelectionNewScreen
//
// Onboarding is shown on EVERY cold start: stored tokens / a previously
// completed onboarding flag must never redirect the app to a dashboard or
// login before onboarding + role selection have been seen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/app/app.dart';
import 'package:parkshare_new/modules/auth/screens/role_selection_new_screen.dart';
import 'package:parkshare_new/modules/onboarding/blue_splash_screen.dart';
import 'package:parkshare_new/modules/onboarding/onboarding_intro_screen.dart';
import 'package:parkshare_new/modules/splash/splash_screen.dart';

/// Pumps the app past the 1.5 s blue splash + one frame hand-off so the
/// deterministic startup controller has run.
Future<void> bootToOnboarding(WidgetTester tester) async {
  await tester.pumpWidget(const ParkShareApp());

  // Cold boot lands on the blue splash, which carries no branding yet.
  expect(find.byType(BlueSplashScreen), findsOneWidget);

  // After the blue splash's 1.5 s hand-off the startup controller runs on the
  // SAME blue screen (SplashScreen), then pushes onboarding.
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump();
  expect(find.byType(SplashScreen), findsOneWidget);

  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  /// Installs a fake flutter_secure_storage. [stored] is returned for every
  /// `read`/`readAll`, which lets a test simulate an already-authenticated
  /// device (stored token) without touching a real Keystore.
  void mockStorage({Map<String, String> stored = const {}}) {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async {
          switch (call.method) {
            case 'readAll':
              return Map<String, String>.from(stored);
            case 'read':
              final args = call.arguments as Map?;
              final key = args?['key']?.toString();
              return key == null ? null : stored[key];
            case 'containsKey':
              final args = call.arguments as Map?;
              final key = args?['key']?.toString();
              return key != null && stored.containsKey(key);
            default:
              return null;
          }
        });
  }

  setUp(() => mockStorage());

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  testWidgets('cold boot: splash -> onboarding page 1 (no white logo page)', (
    tester,
  ) async {
    await bootToOnboarding(tester);

    expect(find.byType(OnboardingIntroScreen), findsOneWidget);
    expect(find.text('Find Nearby Parking'), findsWidgets);
    expect(find.text('Next'), findsWidgets);
    expect(find.text('Skip'), findsWidgets);

    // No white logo screen: neither logo asset is rendered anywhere in the
    // startup flow (the logo-only white page was removed).
    expect(
      find.image(const AssetImage('assets/images/parkshare/logo.png')),
      findsNothing,
    );
    expect(
      find.image(const AssetImage('assets/images/parkshare_logo.png')),
      findsNothing,
    );
  });

  testWidgets('Next on all 3 pages lands on Role Selection', (tester) async {
    await bootToOnboarding(tester);

    expect(find.text('Find Nearby Parking'), findsWidgets);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Book Instantly'), findsWidgets);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Earn with Your Space'), findsWidgets);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.byType(RoleSelectionNewScreen), findsOneWidget);
    expect(find.text('Select Who You Are'), findsWidgets);
    expect(find.byType(OnboardingIntroScreen), findsNothing);
  });

  testWidgets('Skip lands on Role Selection, never login/dashboard', (
    tester,
  ) async {
    await bootToOnboarding(tester);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.byType(RoleSelectionNewScreen), findsOneWidget);
    expect(find.text('Select Who You Are'), findsWidgets);
    expect(find.byType(OnboardingIntroScreen), findsNothing);
  });

  testWidgets(
    'a stored session does NOT bypass onboarding or role selection',
    (tester) async {
      // Simulate a device that already has tokens in secure storage.
      mockStorage(
        stored: const {
          'access_token': 'stored-access-token',
          'refresh_token': 'stored-refresh-token',
          'parkshare_onboarding_completed': 'true',
        },
      );

      await bootToOnboarding(tester);

      // Even with a stored session + completed flag, onboarding is shown.
      expect(find.byType(OnboardingIntroScreen), findsOneWidget);
      expect(find.byType(RoleSelectionNewScreen), findsNothing);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      // Role selection is still shown; startup never jumps to a dashboard.
      expect(find.byType(RoleSelectionNewScreen), findsOneWidget);
    },
  );
}
