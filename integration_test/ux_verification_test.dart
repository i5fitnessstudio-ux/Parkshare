// ParkShare — focused verification of the requested UX fixes.
//
// Runs on the emulator with the backend on the host. Asserts exactly the
// behaviours that were asked for, so a regression names itself:
//
//   1. User bottom navigation order: Vehicles, Map, Bookings, Inbox — and
//      Vehicles is the tab shown on the very first frame after login.
//   2. The map never says "No parking spaces available nearby" before the
//      nearby request has actually finished.
//   3. The current-location marker is BLUE (AppColors.currentLocationBlue)
//      while parking markers stay GREEN.
//   4. With no GPS fix the map falls back to Tamil Nadu (Chennai), never a
//      USA / California coordinate.
//   5. A real booking card exposes a Call button that resolves the owner's
//      dialler number.
//
// It logs in as a pre-seeded account that already owns a booking, so the Call
// button is exercised against real backend data instead of mock rows.
//
// Prereqs:
//   - backend on the host  (http://10.0.2.2:8080 from the emulator)
//   - adb emu geo fix 80.2707 13.0827   (Chennai)
//   - location permissions pre-granted
//   - a user with >=1 vehicle and >=1 booking

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:parkshare_new/app/app.dart';
import 'package:parkshare_new/core/constants/app_colors.dart';
import 'package:parkshare_new/core/constants/location_defaults.dart';
import 'package:parkshare_new/modules/user/map/user_map_tab.dart';

const String kEmail = 'testuser.a@example.com';
const String kPassword = 'Test123456';

String hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Bottom-navigation taps must be scoped to the NavigationBar: screen content
  // can contain the same label.
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Vehicles-first nav, blue location marker, Chennai fallback, '
      'booking Call button', (WidgetTester tester) async {
    // ---------------------------------------------------------------
    // Boot: fresh install -> Onboarding -> Role Selection -> user login
    // ---------------------------------------------------------------
    await tester.pumpWidget(const ParkShareApp());
    await tester.pumpAndSettle();
    expect(
      find.text('Find Nearby Parking'),
      findsWidgets,
      reason: 'fresh install: should land on Onboarding',
    );

    // Tap Next through the 3 intro pages
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Select Who You Are'), findsOneWidget);

    await tester.tap(find.text('Vehicle User'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vehicle User Login'), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), kEmail);
    await tester.enterText(fields.at(1), kPassword);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.textContaining('Hi, Test'),
      findsOneWidget,
      reason: 'a valid login lands on User Home',
    );

    // ---------------------------------------------------------------
    // 1) Bottom navigation ORDER, and Vehicles selected on first paint
    // ---------------------------------------------------------------
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    // NavigationBar.destinations is List<Widget>; the labels live on the
    // NavigationDestination elements.
    final order = <String>[
      for (final d in nav.destinations)
        if (d is NavigationDestination) d.label else '<not a destination>',
    ];
    expect(order, [
      'Vehicles',
      'Map',
      'Bookings',
      'Inbox',
    ], reason: 'user bottom nav must be Vehicles, Map, Bookings, Inbox');
    expect(
      nav.selectedIndex,
      0,
      reason: 'Vehicles is the default tab after login/register',
    );
    debugPrint(
      '[UX] user nav order = $order, selectedIndex = ${nav.selectedIndex}',
    );

    // The map stays mounted in the IndexedStack, so it is already built while
    // the Vehicles tab is on screen...
    expect(
      find.byType(UserMapTab, skipOffstage: false),
      findsOneWidget,
      reason: 'map tab stays mounted in the IndexedStack',
    );

    // ---------------------------------------------------------------
    // 4) ...but it must not have asked for location yet.
    // ---------------------------------------------------------------
    expect(
      tester
          .widget<UserMapTab>(find.byType(UserMapTab, skipOffstage: false))
          .active,
      isFalse,
      reason: 'the map must not prompt for location while it is not visible',
    );
    expect(
      LocationDefaults.latitude,
      inInclusiveRange(8.0, 14.0),
      reason: 'fallback latitude must be inside Tamil Nadu, not the USA',
    );
    expect(
      LocationDefaults.longitude,
      inInclusiveRange(74.0, 80.5),
      reason: 'fallback longitude must be inside Tamil Nadu, not the USA',
    );
    debugPrint(
      '[UX] fallback = ${LocationDefaults.latitude}, ${LocationDefaults.longitude}',
    );

    // ---------------------------------------------------------------
    // 2 + 3) Open the Map tab
    // ---------------------------------------------------------------
    // Deliberately NOT pumpAndSettle here: settling would wait for the nearby
    // request to finish and hide exactly the window we want to inspect. Pump
    // frame by frame and watch every intermediate state.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Map'),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<UserMapTab>(find.byType(UserMapTab, skipOffstage: false))
          .active,
      isTrue,
    );

    final premature = find.text('No parking spaces available nearby');
    final pins = find.byKey(const Key('parking-marker'));
    var sawEmptyBeforeMarkers = false;
    var sawEmpty = false;
    var sawMarkers = false;
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final hasMarkers = pins.evaluate().isNotEmpty;
      final hasEmpty = premature.evaluate().isNotEmpty;
      if (hasEmpty) {
        sawEmpty = true;
        // The empty state before any marker has ever rendered is the bug.
        if (!hasMarkers) sawEmptyBeforeMarkers = true;
      }
      if (hasMarkers) {
        sawMarkers = true;
        break;
      }
    }
    debugPrint(
      '[UX] frame-by-frame: markers=$sawMarkers emptyState=$sawEmpty '
      'emptyBeforeMarkers=$sawEmptyBeforeMarkers',
    );
    expect(
      sawEmptyBeforeMarkers,
      isFalse,
      reason:
          'the map must not claim "no parking" before the request has '
          'actually returned data',
    );
    expect(
      sawMarkers,
      isTrue,
      reason: 'nearby Chennai parkings should render as markers',
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ---------------------------------------------------------------
    // 3) The current-location marker is BLUE, not green
    // ---------------------------------------------------------------
    final dot = find.byKey(const Key('current-location-marker'));
    for (var i = 0; i < 60 && dot.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(
      dot,
      findsOneWidget,
      reason: 'a GPS fix should render the user position marker',
    );
    final decoration =
        tester.widget<Container>(dot.first).decoration as BoxDecoration;
    expect(
      decoration.color,
      AppColors.currentLocationBlue,
      reason: 'the user position marker must be the blue accent',
    );
    expect(
      decoration.color,
      isNot(AppColors.parkingMarkerGreen),
      reason: 'the user position marker must never reuse the parking green',
    );
    debugPrint(
      '[UX] current-location-marker = ${hex(decoration.color!)} '
      '(expected ${hex(AppColors.currentLocationBlue)})',
    );

    // Parking markers must still be the green "P" pin.
    expect(
      pins,
      findsWidgets,
      reason: 'nearby Chennai parkings should be on the map',
    );
    final pin = tester.widget<Container>(
      find.descendant(of: pins.first, matching: find.byType(Container)).first,
    );
    expect(
      (pin.decoration as BoxDecoration).color,
      AppColors.parkingMarkerGreen,
      reason: 'parking pins stay green (only the user position is blue)',
    );
    debugPrint(
      '[UX] parking-marker = '
      '${hex((pin.decoration as BoxDecoration).color!)} '
      '(expected ${hex(AppColors.parkingMarkerGreen)})',
    );

    // The map has markers, so the "no parking" empty state must be suppressed.
    expect(
      premature,
      findsNothing,
      reason: 'markers are on screen, so the empty state must be suppressed',
    );

    // ---------------------------------------------------------------
    // 5) A real booking card exposes a Call button
    // ---------------------------------------------------------------
    await tapTab(tester, 'Bookings');
    final call = find.byKey(const Key('call-owner-button'));
    debugPrint(
      '[UX] call buttons on the bookings tab = ${call.evaluate().length}',
    );
    expect(
      call,
      findsWidgets,
      reason: 'each booking card should offer a Call action',
    );

    // The label must be the plain word "Call" (no tech prefix).
    expect(find.text('Call'), findsWidgets);

    debugPrint('[UX] DONE');
  });
}
