// Responsive layout tests: breakpoint classification, the adaptive navigation
// shell (bottom nav on phones, labelled rail on tablets, extended rail on
// desktop), the content width caps, the adaptive grid/tile-row, and
// provider-free overflow checks on a narrow phone with a 1.3x system text
// scale.
//
// These are deliberately provider-free: they exercise the layout system and
// the screens that do not need auth/backend providers to build.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/modules/auth/screens/login_screen.dart';
import 'package:parkshare_new/modules/legal/legal_document_screen.dart';
import 'package:parkshare_new/modules/onboarding/onboarding_screen.dart';
import 'package:parkshare_new/modules/vehicle/vehicle_form_screen.dart';
import 'package:parkshare_new/shared/widgets/responsive/adaptive_nav_scaffold.dart';
import 'package:parkshare_new/shared/widgets/responsive/responsive_layout.dart';

/// Sizes the test window to [width]x[height] logical pixels and, when
/// [largeText] is set, a 1.3x system text scale. Everything is restored via
/// [addTearDown] so tests never leak view overrides into each other.
void useWindow(
  WidgetTester tester, {
  required double width,
  required double height,
  bool largeText = false,
}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  if (largeText) {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  }
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

const _destinations = [
  AdaptiveDestination(
    icon: Icons.home,
    selectedIcon: Icons.home_outlined,
    label: 'Home',
  ),
  AdaptiveDestination(
    icon: Icons.list_alt,
    selectedIcon: Icons.list_alt_outlined,
    label: 'Bookings',
  ),
];

Widget _shell(ValueChanged<int> onSelected, {required int index}) => MaterialApp(
  home: AdaptiveNavScaffold(
    appBar: AppBar(title: const Text('Shell')),
    body: const Center(child: Text('Content')),
    destinations: _destinations,
    selectedIndex: index,
    onDestinationSelected: onSelected,
  ),
);

void main() {
  group('breakpoint classification', () {
    test('clamps each Material-3 window-size tier', () {
      expect(ResponsiveLayout.fromWidth(320), LayoutBreakpoint.compact);
      expect(ResponsiveLayout.fromWidth(599), LayoutBreakpoint.compact);
      expect(ResponsiveLayout.fromWidth(600), LayoutBreakpoint.medium);
      expect(ResponsiveLayout.fromWidth(839), LayoutBreakpoint.medium);
      expect(ResponsiveLayout.fromWidth(840), LayoutBreakpoint.expanded);
      expect(ResponsiveLayout.fromWidth(1199), LayoutBreakpoint.expanded);
      expect(ResponsiveLayout.fromWidth(1200), LayoutBreakpoint.large);
      expect(ResponsiveLayout.fromWidth(1366), LayoutBreakpoint.large);
      expect(ResponsiveLayout.fromWidth(2560), LayoutBreakpoint.large);
    });
  });

  group('AdaptiveNavScaffold', () {
    testWidgets('compact (<600) keeps the phone NavigationBar, no rail', (
      tester,
    ) async {
      useWindow(tester, width: 360, height: 760);
      var selected = -1;
      await tester.pumpWidget(_shell((i) => selected = i, index: 0));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      // Destination taps still land on the caller's handler.
      await tester.tap(find.text('Bookings'));
      await tester.pump();
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('medium (800) uses a labelled rail, taps forward too', (
      tester,
    ) async {
      useWindow(tester, width: 800, height: 900);
      var selected = -1;
      await tester.pumpWidget(_shell((i) => selected = i, index: 0));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(rail.labelType, NavigationRailLabelType.all);

      await tester.tap(find.text('Bookings'));
      await tester.pump();
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('large (1366) extends the rail for desktop', (tester) async {
      useWindow(tester, width: 1366, height: 900);
      var selected = -1;
      await tester.pumpWidget(_shell((i) => selected = i, index: 0));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        isTrue,
      );

      await tester.tap(find.text('Bookings'));
      await tester.pump();
      expect(selected, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('ConstrainedContent', () {
    Widget capped() => MaterialApp(
      home: Scaffold(
        body: ConstrainedContent(
          maxWidth: ResponsiveLayout.formMaxWidth,
          child: Container(height: 200, color: Colors.red),
        ),
      ),
    );

    testWidgets('centres the capped column on a desktop window', (
      tester,
    ) async {
      useWindow(tester, width: 1366, height: 900);
      await tester.pumpWidget(capped());

      expect(tester.getSize(find.byType(Container)).width,
          ResponsiveLayout.formMaxWidth);
      final left = tester.getTopLeft(find.byType(Container)).dx;
      expect(
        left,
        closeTo((1366 - ResponsiveLayout.formMaxWidth) / 2, 1),
        reason: 'the column is centred in the spare desktop width',
      );
    });

    testWidgets('passes through untouched on a phone', (tester) async {
      useWindow(tester, width: 360, height: 760);
      await tester.pumpWidget(capped());
      expect(tester.getSize(find.byType(Container)).width, 360);
      expect(tester.takeException(), isNull);
    });
  });

  group('ResponsiveGrid', () {
    List<Widget> tiles() {
      return [
        for (var i = 0; i < 6; i++)
          Container(height: 40, color: Colors.blue),
      ];
    }

    testWidgets('two columns on a phone', (tester) async {
      useWindow(tester, width: 360, height: 760);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveGrid(
              maxCrossAxisExtent: 200,
              shrinkWrap: true,
              children: tiles(),
            ),
          ),
        ),
      );

      final a = tester.getTopLeft(find.byType(Container).at(0));
      final b = tester.getTopLeft(find.byType(Container).at(1));
      final c = tester.getTopLeft(find.byType(Container).at(2));
      expect(b.dy, a.dy, reason: 'first two tiles share a row');
      expect(b.dx, greaterThan(a.dx));
      expect(c.dy, greaterThan(a.dy), reason: 'third tile wraps');
    });

    testWidgets('adds columns on a tablet instead of stretching tiles', (
      tester,
    ) async {
      useWindow(tester, width: 800, height: 900);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveGrid(
              maxCrossAxisExtent: 200,
              shrinkWrap: true,
              children: tiles(),
            ),
          ),
        ),
      );

      final a = tester.getTopLeft(find.byType(Container).at(0));
      final d = tester.getTopLeft(find.byType(Container).at(3));
      final e = tester.getTopLeft(find.byType(Container).at(4));
      expect(d.dy, a.dy, reason: 'first four tiles fill one 800 dp row');
      expect(e.dy, greaterThan(a.dy), reason: 'fifth tile wraps');
    });
  });

  group('ResponsiveTileRow', () {
    List<Widget> tiles() {
      return [
        for (var i = 0; i < 4; i++)
          Container(height: 40, color: Colors.green),
      ];
    }

    testWidgets('two-per-row on a phone, one row on a desktop window', (
      tester,
    ) async {
      useWindow(tester, width: 360, height: 760);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveTileRow(minTileWidth: 140, children: tiles()),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byType(Container).at(2)).dy,
        greaterThan(tester.getTopLeft(find.byType(Container).at(0)).dy),
        reason: '360 dp fits two tiles per row, so the third wraps',
      );

      useWindow(tester, width: 1366, height: 900);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveTileRow(minTileWidth: 140, children: tiles()),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byType(Container).at(3)).dy,
        tester.getTopLeft(find.byType(Container).at(0)).dy,
        reason: 'on desktop all four tiles fit on one row',
      );
    });
  });

  group('narrow phone + 1.3x text scale (provider-free, no overflow)', () {
    Future<void> pumpNoOverflow(WidgetTester tester, Widget widget) async {
      useWindow(tester, width: 320, height: 568, largeText: true);
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'screen must not overflow');
    }

    testWidgets('login screen', (tester) async {
      await pumpNoOverflow(
        tester,
        const MaterialApp(home: LoginScreen(arguments: 'user')),
      );
    });

    testWidgets('onboarding carousel', (tester) async {
      await pumpNoOverflow(
        tester,
        const MaterialApp(home: OnboardingScreen()),
      );
    });

    testWidgets('legal document reader', (tester) async {
      await pumpNoOverflow(
        tester,
        const MaterialApp(home: LegalDocumentScreen.terms()),
      );
    });

    testWidgets('vehicle form', (tester) async {
      await pumpNoOverflow(
        tester,
        const MaterialApp(home: Scaffold(body: VehicleFormScreen())),
      );
    });

    testWidgets('adaptive shell with all destinations', (tester) async {
      await pumpNoOverflow(tester, _shell((_) {}, index: 0));
    });
  });
}