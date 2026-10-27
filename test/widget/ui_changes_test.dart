// Widget tests for the round of UI changes: vehicle color removed, password
// show/hide toggles, searchable city/state fields, feet-based units, the four
// per-vehicle rental plans and the amenity list cleanup.
//
// These are the things that would regress silently: a color section creeping
// back, a password field left visible, a suggestion list that never opens, or
// a plan switch that writes the wrong draft flag.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/modules/auth/screens/login_screen.dart';
import 'package:parkshare_new/modules/owner/add_parking/parking_draft.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/amenities_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/details_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/dimensions_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/rental_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/spaces_step.dart';
import 'package:parkshare_new/modules/vehicle/vehicle_form_screen.dart';
import 'package:parkshare_new/shared/models/parking_space.dart';

/// Wraps a widget in the minimum Material scaffolding it expects, on a
/// phone-shaped column (360 wide) that stays inside the 800x600 test window —
/// anything taller would render below the window and never receive taps.
Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: StatefulBuilder(
      builder: (context, setState) =>
          SizedBox(width: 360, height: 560, child: child),
    ),
  ),
);

/// A step only re-renders when someone calls setState, so [build] is handed
/// the `onChanged` the step calls after it mutates the draft.
Widget stepHost(Widget Function(VoidCallback onChanged) build) => host(
  StatefulBuilder(builder: (context, setState) => build(() => setState(() {}))),
);

/// Scrolls [finder] into view the way a user would, then returns it. The
/// steps are lazily built, so a field below the fold does not exist yet.
Future<Finder> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
  return finder;
}

/// The city/state field of the details step, found by its placeholder (both
/// are plain `TextField`s inside `RawAutocomplete`).
Finder placeField(String hint) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == hint,
);

/// One of the autocomplete suggestion rows (a tappable `InkWell`), which is
/// distinct from the field's own hint text.
Finder suggestion(String option) => find.widgetWithText(InkWell, option);

/// The suffix unit ('ft', 'm') of every measurement field currently built.
List<String> suffixUnits(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .map((f) => f.decoration?.suffixText)
    .whereType<String>()
    .toList(growable: false);

/// A draft with every measurement filled, so area/warning readouts render.
ParkingDraft measuredDraft() => ParkingDraft()
  ..lengthM = 5
  ..widthM = 2.5
  ..heightM = 2.5
  ..entranceWidthM = 2.2
  ..entranceHeightM = 2.5;

void main() {
  group('Password show/hide (owner & vehicle user login)', () {
    Finder passwordField() =>
        find.byWidgetPredicate((w) => w is TextField && w.obscureText);

    for (final role in ['owner', 'user']) {
      testWidgets('$role: password starts hidden and the eye toggles it', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(home: LoginScreen(arguments: role)),
        );
        await tester.pumpAndSettle();

        // Default state: exactly one obscured field — the password.
        expect(passwordField(), findsOneWidget);
        expect(find.byTooltip('Show password'), findsOneWidget);
        expect(find.byTooltip('Hide password'), findsNothing);

        // Tap the eye -> visible.
        await tester.ensureVisible(find.byTooltip('Show password'));
        await tester.tap(find.byTooltip('Show password'));
        await tester.pumpAndSettle();
        expect(passwordField(), findsNothing, reason: 'no longer obscured');
        expect(find.byTooltip('Hide password'), findsOneWidget);

        // Tap again -> hidden again.
        await tester.tap(find.byTooltip('Hide password'));
        await tester.pumpAndSettle();
        expect(passwordField(), findsOneWidget);
        expect(find.byTooltip('Show password'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Vehicle form (color removed, feet units)', () {
    testWidgets('the Color section is gone and the rest is intact', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VehicleFormScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Color'), findsNothing);
      expect(find.text('Vechicle Number'), findsOneWidget);
      expect(find.text('Vehicle Type'), findsOneWidget);
      expect(find.text('Save & Find Parking'), findsOneWidget);

      // The list is lazy: walk down it and check the fields as they build.
      await scrollTo(tester, find.text('Brand'));
      expect(find.text('Brand'), findsOneWidget);
      await scrollTo(tester, find.text('Model'));
      expect(find.text('Model'), findsOneWidget);
      await scrollTo(tester, find.text('Dimensions (feet)'));
      expect(find.text('Dimensions (feet)'), findsOneWidget);
      expect(find.text('Color'), findsNothing, reason: 'gone at every scroll');
      expect(tester.takeException(), isNull);
    });

    testWidgets('every dimension field is in feet, never metres', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: VehicleFormScreen())),
      );
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('Dimensions (feet)'));
      final units = suffixUnits(tester);
      expect(units, hasLength(3), reason: 'Length/Width/Height');
      expect(units, everyElement('ft'));
      expect(find.textContaining('metres'), findsNothing);
      expect(find.textContaining('sq m'), findsNothing);
    });
  });

  group('Owner details step (parking name + searchable places)', () {
    testWidgets('the field is labelled "Parking space name *"', (tester) async {
      final draft = ParkingDraft();
      await tester.pumpWidget(
        stepHost(
          (onChanged) => DetailsStep(draft: draft, onChanged: onChanged),
        ),
      );
      expect(find.text('Parking space name *'), findsOneWidget);
      expect(find.text('Parking name *'), findsNothing);
    });

    testWidgets('typing a city shows suggestions and tapping one fills it', (
      tester,
    ) async {
      final draft = ParkingDraft();
      await tester.pumpWidget(
        stepHost(
          (onChanged) => DetailsStep(draft: draft, onChanged: onChanged),
        ),
      );

      await tester.enterText(placeField('Mumbai'), 'kol');
      await tester.pumpAndSettle();

      expect(suggestion('Kolkata'), findsOneWidget);
      expect(suggestion('Kolhapur'), findsOneWidget);

      await tester.tap(suggestion('Kolkata'));
      await tester.pumpAndSettle();
      expect(draft.city, 'Kolkata', reason: 'tapping writes the draft');
    });

    testWidgets('a state suggestion fills the state field', (tester) async {
      final draft = ParkingDraft();
      await tester.pumpWidget(
        stepHost(
          (onChanged) => DetailsStep(draft: draft, onChanged: onChanged),
        ),
      );

      await tester.enterText(placeField('Maharashtra'), 'mahar');
      await tester.pumpAndSettle();
      expect(suggestion('Maharashtra'), findsOneWidget);

      await tester.tap(suggestion('Maharashtra'));
      await tester.pumpAndSettle();
      expect(draft.state, 'Maharashtra');
      expect(draft.city, isEmpty, reason: 'the other field is untouched');
    });

    testWidgets('a place that is not on the list can still be typed', (
      tester,
    ) async {
      final draft = ParkingDraft();
      await tester.pumpWidget(
        stepHost(
          (onChanged) => DetailsStep(draft: draft, onChanged: onChanged),
        ),
      );
      await tester.enterText(placeField('Mumbai'), 'Paldi');
      await tester.pumpAndSettle();
      expect(draft.city, 'Paldi', reason: 'nothing is ever forced');
      expect(find.text('Kolkata'), findsNothing, reason: 'no dropdown opened');
    });
  });

  group('Dimensions step (feet everywhere)', () {
    testWidgets('helper text says feet and every field is in ft', (
      tester,
    ) async {
      final draft = measuredDraft();
      await tester.pumpWidget(
        stepHost(
          (onChanged) => DimensionsStep(draft: draft, onChanged: onChanged),
        ),
      );

      expect(
        find.text(
          'Enter plain numbers in feet — e.g. 16.40 (never '
          '"16.40 ft").',
        ),
        findsOneWidget,
      );

      // Plot row (built immediately): three ft fields.
      final plotUnits = suffixUnits(tester);
      expect(plotUnits, hasLength(3), reason: 'plot Length/Width/Height');
      expect(plotUnits, everyElement('ft'));

      // Gate row builds only once scrolled into view: three more ft fields.
      await scrollTo(tester, find.text('Gate height *'));
      final gateUnits = suffixUnits(tester);
      expect(gateUnits.length, greaterThanOrEqualTo(3));
      expect(gateUnits, everyElement('ft'));

      expect(find.textContaining('metres'), findsNothing);
      expect(find.textContaining('sq m'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the usable area readout is in square feet', (tester) async {
      final draft = measuredDraft();
      await tester.pumpWidget(
        stepHost(
          (onChanged) => DimensionsStep(draft: draft, onChanged: onChanged),
        ),
      );
      await scrollTo(tester, find.textContaining('Total usable floor area'));
      expect(find.textContaining('Total usable floor area'), findsOneWidget);
      expect(find.textContaining('sq ft'), findsWidgets);
    });

    testWidgets('plot and gate rows are both Length, Width, Height', (
      tester,
    ) async {
      final draft = measuredDraft();
      await tester.pumpWidget(
        stepHost(
          (onChanged) => DimensionsStep(draft: draft, onChanged: onChanged),
        ),
      );

      // Plot block: all three in one row, so x increases with the order.
      final plot = [
        find.text('Length *'),
        find.text('Width *'),
        find.text('Height *'),
      ];
      for (final f in plot) {
        expect(f, findsOneWidget);
      }
      final plotX = plot.map((f) => tester.getCenter(f).dx).toList();
      expect(plotX, List.of(plotX)..sort(), reason: 'left-to-right');

      // Gate block, scrolled into view first (it sits far below the fold).
      await scrollTo(tester, find.text('Gate length'));
      final gate = [
        find.text('Gate length'),
        find.text('Gate width *'),
        find.text('Gate height *'),
      ];
      for (final f in gate) {
        expect(f, findsOneWidget);
      }
      final gateX = gate.map((f) => tester.getCenter(f).dx).toList();
      expect(gateX, List.of(gateX)..sort(), reason: 'left-to-right');
      expect(tester.takeException(), isNull);
    });
  });

  group('Parking spaces step (per-space dimensions in feet)', () {
    testWidgets('every space dimension field is in ft', (tester) async {
      final draft = ParkingDraft()
        ..lengthM = 5
        ..widthM = 2.5
        ..heightM = 2.5
        ..setCapacity(ParkingSpaceVehicleType.car, 1);
      await tester.pumpWidget(
        stepHost((onChanged) => SpacesStep(draft: draft, onChanged: onChanged)),
      );
      await scrollTo(tester, find.text('Car space 1'));

      final units = suffixUnits(tester);
      expect(units, isNotEmpty);
      expect(units, everyElement('ft'));
      expect(find.textContaining('metres'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Rental plans (four independent plans)', () {
    testWidgets('car and bike each get their own monthly and yearly switch', (
      tester,
    ) async {
      final draft = ParkingDraft();
      await tester.pumpWidget(
        stepHost((onChanged) => RentalStep(draft: draft, onChanged: onChanged)),
      );

      expect(find.text('Car plans'), findsOneWidget);
      expect(find.text('Bike plans'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(4));
      // Everything starts off, so no amount field is drawn yet.
      expect(find.text('Monthly rent *'), findsNothing);
      expect(find.text('Yearly rent *'), findsNothing);

      // First switch = car monthly.
      await tester.tap(find.byType(Switch).at(0));
      await tester.pumpAndSettle();
      expect(draft.carMonthlyEnabled, isTrue);
      expect(draft.bikeMonthlyEnabled, isFalse, reason: 'independent');
      expect(find.text('Monthly rent *'), findsOneWidget);

      // Last switch = bike yearly — scroll it into the window first.
      await scrollTo(tester, find.byType(Switch).at(3));
      await tester.tap(find.byType(Switch).at(3));
      await tester.pumpAndSettle();
      expect(draft.bikeYearlyEnabled, isTrue);
      expect(draft.carYearlyEnabled, isFalse, reason: 'independent');
      expect(find.text('Yearly rent *'), findsOneWidget);
      expect(find.text('Monthly rent *'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('turning a plan off removes its amount field again', (
      tester,
    ) async {
      final draft = ParkingDraft()..carMonthlyEnabled = true;
      await tester.pumpWidget(
        stepHost((onChanged) => RentalStep(draft: draft, onChanged: onChanged)),
      );
      expect(find.text('Monthly rent *'), findsOneWidget);

      await tester.tap(find.byType(Switch).at(0));
      await tester.pumpAndSettle();
      expect(draft.carMonthlyEnabled, isFalse);
      expect(find.text('Monthly rent *'), findsNothing);
    });
  });

  group('Amenities step (removed entries + styling)', () {
    testWidgets('car/two-wheeler allowances are gone, the rest remain', (
      tester,
    ) async {
      final draft = ParkingDraft();
      await tester.pumpWidget(
        stepHost(
          (onChanged) => AmenitiesStep(draft: draft, onChanged: onChanged),
        ),
      );

      expect(find.text('Two Wheeler Allowed'), findsNothing);
      expect(find.text('Car Allowed'), findsNothing);
      expect(ParkingAmenity.all, hasLength(9));
      for (final amenity in ParkingAmenity.all) {
        expect(find.text(amenity), findsOneWidget, reason: amenity);
      }
    });

    testWidgets('tiles are a 2-column grid with bold labels, tap toggles', (
      tester,
    ) async {
      final draft = ParkingDraft();
      await tester.pumpWidget(
        stepHost(
          (onChanged) => AmenitiesStep(draft: draft, onChanged: onChanged),
        ),
      );

      // Responsive tiles: the grid now derives its column count from the
      // available width (2 columns on a phone, more on a tablet) and its tile
      // height tracks the system text scale instead of a hard-coded 84 dp.
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate = grid.childrenDelegate as SliverChildListDelegate;
      expect(delegate.children, hasLength(9));
      expect(
        grid.gridDelegate,
        isA<SliverGridDelegateWithMaxCrossAxisExtent>()
            .having((g) => g.maxCrossAxisExtent, 'maxCrossAxisExtent', 200)
            .having((g) => g.mainAxisExtent, 'mainAxisExtent', 84),
      );

      // On the 360 dp host it still flows as two columns: the first two tiles
      // share a row, the third starts the next one.
      final first = tester.getTopLeft(
        find.widgetWithText(FilterChip, ParkingAmenity.all[0]),
      );
      final second = tester.getTopLeft(
        find.widgetWithText(FilterChip, ParkingAmenity.all[1]),
      );
      final third = tester.getTopLeft(
        find.widgetWithText(FilterChip, ParkingAmenity.all[2]),
      );
      expect(second.dy, first.dy, reason: 'first two tiles share a row');
      expect(second.dx, greaterThan(first.dx));
      expect(third.dy, greaterThan(first.dy), reason: 'third tile wraps');

      // Bold (w700) label inside a chip.
      final chip = find.widgetWithText(FilterChip, ParkingAmenity.cctv);
      expect(chip, findsOneWidget);
      final label = tester.widget<Text>(
        find.descendant(of: chip, matching: find.text(ParkingAmenity.cctv)),
      );
      expect(label.style?.fontWeight, FontWeight.w700);

      // Selection still toggles the draft.
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(draft.amenities, contains(ParkingAmenity.cctv));

      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(draft.amenities, isNot(contains(ParkingAmenity.cctv)));
      expect(tester.takeException(), isNull);
    });
  });
}
