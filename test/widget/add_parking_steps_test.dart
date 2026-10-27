import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/modules/owner/add_parking/parking_draft.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/about_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/capacity_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/spaces_step.dart';
import 'package:parkshare_new/shared/models/parking_space.dart';

/// Wraps a step in the minimum Material scaffolding it expects, at the size of
/// a real phone (360 x 760 logical pixels).
///
/// [build] is handed the `onChanged` the step calls after it mutates the draft.
/// The draft is a plain mutable object, so a step only re-renders when someone
/// calls setState — the real wizard does that, and this host has to as well,
/// otherwise every assertion after a tap reads a stale tree.
Widget host(Widget Function(VoidCallback onChanged) build) => MaterialApp(
  home: Scaffold(
    body: StatefulBuilder(
      builder: (context, setState) => SizedBox(
        width: 360,
        height: 760,
        child: build(() => setState(() {})),
      ),
    ),
  ),
);

/// Scrolls [finder] into view the way a user would, then returns it.
/// The test font is a fixed-width square per glyph, so the steps are much
/// taller here than on a device and a row can start off-screen.
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

/// Drags the step's list until [finder] matches at least [count] widgets.
///
/// `scrollUntilVisible` needs a finder that can be empty, so it cannot drive a
/// chained `.at(1)`. This counts instead, which is what a lazily-built list of
/// "N of these" rows actually needs.
Future<void> scrollUntilCount(
  WidgetTester tester,
  Finder finder,
  int count,
) async {
  for (var i = 0; i < 12; i++) {
    if (tester.widgetList(finder).length >= count) return;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
  }
  fail(
    'never scrolled $count ${finder.describeMatch(Plurality.one)} into view',
  );
}

ParkingDraft draftWith({int cars = 0, int bikes = 0}) => ParkingDraft()
  ..lengthM = 5
  ..widthM = 2.5
  ..heightM = 2.5
  ..entranceWidthM = 2.5
  ..entranceHeightM = 2.5
  ..setCapacity(ParkingSpaceVehicleType.car, cars)
  ..setCapacity(ParkingSpaceVehicleType.bike, bikes);

void main() {
  group('CapacityStep', () {
    testWidgets(
      'the + stepper really creates slot rows and moves the counter',
      (tester) async {
        final draft = draftWith();
        await tester.pumpWidget(
          host((onChanged) => CapacityStep(draft: draft, onChanged: onChanged)),
        );

        expect(find.text('None'), findsNWidgets(2));
        expect(
          find.textContaining('Add at least one car space or one bike space'),
          findsOneWidget,
        );

        // The stepper used to be frozen: it changed a cached number but never
        // created a row, so the spaces step stayed empty.
        await tester.tap(find.bySemanticsLabel('One more car space'));
        await tester.pumpAndSettle();

        expect(draft.carSpaceCount, 1);
        expect(
          draft.maximumCars,
          1,
          reason: 'the counter must follow the rows',
        );
        expect(find.text('1 space'), findsOneWidget);
        expect(find.text('None'), findsOneWidget); // bikes still zero

        await tester.tap(find.bySemanticsLabel('One more car space'));
        await tester.pumpAndSettle();
        expect(draft.carSpaceCount, 2);
        expect(find.text('2 spaces'), findsOneWidget);
      },
    );

    testWidgets('the - stepper removes a row, down to a valid "no cars"', (
      tester,
    ) async {
      final draft = draftWith(cars: 2, bikes: 1);
      await tester.pumpWidget(
        host((onChanged) => CapacityStep(draft: draft, onChanged: onChanged)),
      );
      expect(find.text('2 spaces'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('One fewer car space'));
      await tester.pumpAndSettle();
      expect(draft.carSpaceCount, 1);
      expect(draft.maximumCars, 1);
      expect(draft.bikeSpaceCount, 1, reason: 'the other pool is untouched');
      expect(draft.vehicleType, 'BOTH');

      await tester.tap(find.bySemanticsLabel('One fewer car space'));
      await tester.pumpAndSettle();
      expect(draft.carSpaceCount, 0);
      expect(draft.vehicleType, 'BIKE');
      expect(
        find.textContaining('Add at least one car space or one bike space'),
        findsNothing,
      );
    });

    testWidgets('a zero/zero draft is blocked with a plain-English reason', (
      tester,
    ) async {
      final draft = draftWith();
      await tester.pumpWidget(
        host((onChanged) => CapacityStep(draft: draft, onChanged: onChanged)),
      );
      await scrollTo(
        tester,
        find.widgetWithText(SwitchListTile, 'Allow mixed parking'),
      );
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Allow mixed parking'),
      );
      await tester.pumpAndSettle();

      expect(draft.allowMixedParking, isTrue);
      expect(
        draft.spacesError,
        'Add at least one parking space (car or bike).',
      );
      expect(
        find.textContaining('nobody can book this parking'),
        findsOneWidget,
      );
    });

    testWidgets('mixed parking never implies a car may use a bike space', (
      tester,
    ) async {
      final draft = draftWith(cars: 1);
      await tester.pumpWidget(
        host((onChanged) => CapacityStep(draft: draft, onChanged: onChanged)),
      );
      await scrollTo(
        tester,
        find.widgetWithText(SwitchListTile, 'Allow mixed parking'),
      );
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Allow mixed parking'),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('bike spaces stay reserved for bikes'),
        findsOneWidget,
      );
    });
  });

  group('SpacesStep', () {
    testWidgets('car and bike are two tabs of the one step', (tester) async {
      final draft = draftWith(cars: 2, bikes: 1);
      await tester.pumpWidget(
        host((onChanged) => SpacesStep(draft: draft, onChanged: onChanged)),
      );

      expect(find.text('Cars (2)'), findsOneWidget);
      expect(find.text('Bikes (1)'), findsOneWidget);
      expect(find.text('Car space 1'), findsOneWidget);
      expect(find.text('Bike space 1'), findsNothing);

      await tester.tap(find.text('Bikes (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Bike space 1'), findsOneWidget);
      expect(find.text('Car space 1'), findsNothing);
    });

    testWidgets('a type with zero spaces gets no tab at all', (tester) async {
      final draft = draftWith(cars: 2);
      await tester.pumpWidget(
        host((onChanged) => SpacesStep(draft: draft, onChanged: onChanged)),
      );
      // One type only -> the tab strip is not drawn at all, so there is no
      // "Bikes (0)" tab for the owner to click into an empty list.
      expect(find.text('Bikes (0)'), findsNothing);
      expect(find.textContaining('Bikes'), findsNothing);
      expect(find.text('Car space 1'), findsOneWidget);
      await scrollTo(tester, find.text('Add Car Space'));
      expect(find.text('Add Car Space'), findsOneWidget);
    });

    testWidgets('Add space creates a real, sequential, bike-sized row', (
      tester,
    ) async {
      final draft = draftWith(cars: 1);
      await tester.pumpWidget(
        host((onChanged) => SpacesStep(draft: draft, onChanged: onChanged)),
      );

      await scrollTo(tester, find.text('Add Car Space'));
      await tester.tap(find.text('Add Car Space'));
      await tester.pumpAndSettle();
      expect(draft.carSpaceCount, 2);
      expect(draft.carSpaces.map((s) => s.spaceCode), ['C1', 'C2']);
      expect(draft.maximumCars, 2);
    });

    testWidgets(
      'deleting the middle row removes the right one and closes the gap',
      (tester) async {
        final draft = draftWith(cars: 3);
        await tester.pumpWidget(
          host((onChanged) => SpacesStep(draft: draft, onChanged: onChanged)),
        );

        // C2 is the middle row: the assertion is about WHICH row went, not just
        // the count. The list builds lazily, so the second card has to be
        // scrolled into view before its delete button exists.
        await scrollUntilCount(tester, find.byTooltip('Remove this space'), 2);
        await tester.tap(find.byTooltip('Remove this space').at(1));
        await tester.pumpAndSettle();
        expect(find.text('Remove C2?'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
        await tester.pumpAndSettle();

        expect(draft.carSpaceCount, 2);
        expect(draft.carSpaces.map((s) => s.spaceCode), [
          'C1',
          'C2',
        ], reason: 'codes must be re-indexed so no gap is left behind');
        expect(draft.maximumCars, 2);
        expect(draft.vehicleType, 'CAR');
      },
    );

    testWidgets('an empty draft explains what is missing instead of crashing', (
      tester,
    ) async {
      final draft = draftWith();
      await tester.pumpWidget(
        host((onChanged) => SpacesStep(draft: draft, onChanged: onChanged)),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('parking space'), findsWidgets);
    });

    testWidgets(
      'the car and bike tabs are each reachable by an accessible label',
      (tester) async {
        final draft = draftWith(cars: 1, bikes: 2);
        await tester.pumpWidget(
          host((onChanged) => SpacesStep(draft: draft, onChanged: onChanged)),
        );
        expect(
          find.bySemanticsLabel(RegExp('^Car spaces tab')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('^Bike spaces tab')),
          findsOneWidget,
        );
      },
    );

    testWidgets('no slot row overflows its card on a narrow phone', (
      tester,
    ) async {
      final draft = draftWith(cars: 2, bikes: 1);
      await tester.pumpWidget(
        host((onChanged) => SpacesStep(draft: draft, onChanged: onChanged)),
      );
      // The tips card heading is the tightest row in the step.
      await scrollTo(tester, find.text('Tips for accurate spaces'));
      expect(tester.takeException(), isNull);
      expect(find.text('Tips for accurate spaces'), findsOneWidget);
    });
  });

  group('AboutStep', () {
    testWidgets('accepts-vehicles is a read-only recap of the real slots', (
      tester,
    ) async {
      final draft = draftWith(cars: 2, bikes: 1);
      await tester.pumpWidget(
        host((onChanged) => AboutStep(draft: draft, onChanged: onChanged)),
      );

      expect(find.text('Car spaces'), findsOneWidget);
      expect(find.text('Bike spaces'), findsOneWidget);
      expect(
        find.textContaining('Accepts 3 spaces (2 car, 1 bike)'),
        findsOneWidget,
      );
      // The old editable segmented control assigned the (now derived)
      // vehicleType, so it must be gone for good.
      expect(find.text('Both'), findsNothing);
      expect(find.text('Cars only'), findsNothing);
    });

    testWidgets(
      'a bike-only listing says so, and says it is not bookable yet',
      (tester) async {
        final draft = draftWith(bikes: 2);
        await tester.pumpWidget(
          host((onChanged) => AboutStep(draft: draft, onChanged: onChanged)),
        );
        expect(
          find.textContaining('Accepts 2 spaces (0 car, 2 bike)'),
          findsOneWidget,
        );

        draft.spaces.clear();
        draft.syncCapacityCounters();
        await tester.pumpWidget(
          host((onChanged) => AboutStep(draft: draft, onChanged: onChanged)),
        );
        expect(find.textContaining('will not be bookable'), findsOneWidget);
      },
    );
  });
}
