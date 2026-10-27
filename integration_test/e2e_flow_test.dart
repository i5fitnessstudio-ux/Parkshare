// ParkShare Phase 2-5 — end-to-end owner + vehicle-user flow test
// (runs on the emulator with the backend on the host).
//
// Covers, in order:
//   1.  Vehicle User: register -> add a vehicle (drives the fit check)
//   2.  Parking Owner: register -> publish a parking via the 8-step wizard
//       (PHOTO from the deterministic E2E picker, real coords, plain-number
//       dimensions, monthly rent, amenities)
//   3.  Vehicle User: map search -> REAL green P marker -> preview card ->
//       detail with frontend fit check ('Perfect Fit')
//   4.  Book -> server-computed amount -> payment screen offering UPI and
//       Cash on Delivery ONLY (UPI preselected, the owner's UPI id shown).
//       The booking is left unpaid so it still holds the slot.
//   5.  Overlap booking attempt -> rejected by the backend (409)
//   6.  Pay with Cash on Delivery from the Bookings tab -> COD screen
//       ("Please contact your parking owner") -> booking COD_PENDING:
//       no money moved and the booking is NOT confirmed
//   7.  Owner: bookings tab shows the joined user/parking/vehicle/payment
//       data + the COD badge; dashboard proves pending cash is NOT earnings
//       and does NOT occupy the slot; "Mark COD Received" -> confirm dialog
//       -> COD Paid / Confirmed; detail sheet with Call / Message; chat
//       sends a real message
//   8.  Owner dashboard after the confirmation: real earnings (₹3,000),
//       Occupied 1 and no cash left to collect
//
// English is used throughout so UI assertions are stable.
//
// Prereqs (see README / report):
//   - backend running on the host  (http://10.0.2.2:8080 from the emulator)
//   - the Step-2 parking address must geocode within the app's nearby radius
//     of LocationService.e2ePoint (19.0760, 72.8777 — Kurla West, Mumbai),
//     because the user map searches around the DEVICE position. The address
//     used below ("Pipe Road, Kurla West, …") measures 413 m from that point.
//     GPS itself is not read: --dart-define=E2E_TEST=true returns the fixed
//     point, so `adb emu geo fix 72.8777 19.0760` is NOT required.
//   - permissions pre-granted:
//       adb shell pm grant com.example.parkshare_new \
//           android.permission.ACCESS_FINE_LOCATION
//       adb shell pm grant com.example.parkshare_new \
//           android.permission.ACCESS_COARSE_LOCATION
//   - launch with --dart-define=E2E_TEST=true (deterministic photo picker)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:parkshare_new/app/app.dart';
import 'package:parkshare_new/core/network/error_messages.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/details_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/dimensions_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/location_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/rental_step.dart';
import 'package:parkshare_new/modules/owner/add_parking/steps/review_step.dart';
import 'package:parkshare_new/modules/owner/bookings/owner_booking_detail_sheet.dart';
import 'package:parkshare_new/modules/owner/home/owner_dashboard_screen.dart';
import 'package:parkshare_new/modules/user/map/user_map_tab.dart';
import 'package:parkshare_new/shared/widgets/terms_consent_checkbox.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Field entry scoped to a wizard step (IndexedStack keeps every step in
  // the tree, so unscoped finders would hit hidden fields).
  Future<void> enterInStep(
    WidgetTester tester,
    Type step,
    int index,
    String text,
  ) async {
    final fields = find.descendant(
      of: find.byType(step),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(index), text);
    await tester.pump(const Duration(milliseconds: 200));
  }

  // Bottom-navigation taps must be scoped to the NavigationBar: screen content
  // can contain the same label (e.g. the dashboard's "Parkings" stat card).
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The payment CTA is disabled and shows a spinner until the SELECTED
  // owner's UPI id + contact have loaded, so the call-to-action label is the
  // reliable "payment screen is ready" signal.
  Future<void> waitForCta(WidgetTester tester, String label) async {
    for (var i = 0; i < 40 && find.text(label).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
  }

  // A ListView builds lazily, so a widget below the fold does not exist in the
  // tree at all until it is scrolled into view: scrollUntilVisible is the only
  // safe way to reach it (ensureVisible fails on an unbuilt widget).
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  // Create Account requires the mandatory Terms & Conditions / Privacy Policy
  // consent: the Continue button stays disabled until the box is ticked, and
  // the two links open the real legal documents.
  Future<void> acceptTermsAndPrivacy(WidgetTester tester) async {
    final consent = find.byType(TermsConsentCheckbox);
    await tester.ensureVisible(consent);
    await tester.pump(const Duration(milliseconds: 200));

    final checkbox = find.descendant(
      of: consent,
      matching: find.byType(Checkbox),
    );
    expect(
      tester.widget<Checkbox>(checkbox).value,
      isFalse,
      reason: 'consent must start unchecked',
    );
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Checkbox>(checkbox).value,
      isTrue,
      reason: 'tapping the box must record the consent',
    );
  }

  // Reads the number printed in the dashboard stat card whose caption is
  // `label`. _StatCard renders exactly two Texts — value first, caption
  // second — so the innermost Column ancestor holding those two Texts is the
  // card. Used instead of asserting bare '1'/'0' strings, which would match
  // any number on screen.
  String statValue(String label) {
    final columns = find.ancestor(
      of: find.text(label),
      matching: find.byType(Column),
    );
    for (final column in columns.evaluate()) {
      final texts = find
          .descendant(
            of: find.byElementPredicate((e) => e == column),
            matching: find.byType(Text),
          )
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .toList();
      if (texts.length == 2 && texts.last == label) return texts.first;
    }
    return '';
  }

  testWidgets('Phase 2-5: owner publish -> user map/fit/book/pay COD -> overlap 409 -> '
      'owner collects cash/dashboard/chat', (WidgetTester tester) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final userEmail = 'e2euser$stamp@parkshare.com';
    final ownerEmail = 'e2eowner$stamp@parkshare.com';
    const password = 'secret123';
    final parkingName = 'E2E Greenview $stamp';

    // ---------------------------------------------------------------
    // Boot: no session (fresh install) -> Onboarding -> Role Selection
    // ---------------------------------------------------------------
    await tester.pumpWidget(const ParkShareApp());
    await tester.pumpAndSettle();
    debugPrint('[E2E] boot: onboarding shown');
    expect(
      find.text('Find parking near you'),
      findsOneWidget,
      reason: 'fresh install: should land on Onboarding',
    );

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    debugPrint('[E2E] role selection shown');
    expect(find.text('What best describes you?'), findsOneWidget);

    // ---------------------------------------------------------------
    // 1) Vehicle User: register
    // ---------------------------------------------------------------
    await tester.tap(find.text('Vehicle User'));
    await tester.pumpAndSettle();

    final createAccount = find.text('Create Account');
    await tester.ensureVisible(createAccount);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(createAccount);
    await tester.pumpAndSettle();

    // Create Account is ONE page: name, email, phone, UPI ID (optional for a
    // vehicle user), password, confirm password. The old separate
    // "Create Password" step has been removed.
    final regFields = find.byType(TextFormField);
    expect(regFields, findsNWidgets(6));
    await tester.enterText(regFields.at(0), 'Test Driver');
    await tester.enterText(regFields.at(1), userEmail);
    await tester.enterText(regFields.at(2), '9876500007');
    await tester.enterText(regFields.at(3), ''); // UPI optional for users
    await tester.enterText(regFields.at(4), password);
    await tester.enterText(regFields.at(5), password);

    // Mandatory legal consent before the Continue button enables.
    await acceptTermsAndPrivacy(tester);

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Continue'),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();
    debugPrint('[E2E] user registered, home shown');

    expect(
      find.textContaining('Hi, Test'),
      findsOneWidget,
      reason: 'registered vehicle user lands on User Home',
    );

    // Add a bike with real dimensions (drives the fit check).
    await tapTab(tester, 'Vehicles');
    expect(find.text('No vehicles added'), findsOneWidget);
    await tester.tap(find.text('Add vehicle'));
    await tester.pumpAndSettle();
    debugPrint(
      '[E2E] after Add vehicle tap: formTitle='
      '${find.text("Vehicle type").evaluate().length} '
      'fields=${find.byType(TextFormField).evaluate().length} '
      'navBar=${find.byType(NavigationBar).evaluate().length}',
    );

    // The Add-Vehicle form is a ListView: focusing a field raises the soft
    // keyboard, which shrinks the viewport and UN-BUILDS the off-screen
    // MeterFields, so an index-based TextFormField finder goes stale between
    // (e.g.) index 3 and 4. Fix: drive each field via (a) unfocus after every
    // entry to collapse the keyboard, and (b) dragUntilVisible for the bottom
    // dimension fields.
    Future<void> fillVehField(int index, String value) async {
      final target = find.byType(TextFormField).at(index);
      // If the field is off-screen (not built), drag the ListView until it is.
      if (target.evaluate().isEmpty) {
        await tester.dragUntilVisible(
          target,
          find.byType(ListView),
          const Offset(0, -120),
        );
      }
      await tester.pumpAndSettle();
      await tester.enterText(target, value);
      await tester.pump(const Duration(milliseconds: 120));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    await fillVehField(0, 'Honda');
    await fillVehField(1, 'Activa 6G');
    await fillVehField(2, 'MH12AB1234');
    // L / W / H (plain-number metre fields, indices 3..5).
    await fillVehField(3, '1.80');
    await fillVehField(4, '0.70');
    await fillVehField(5, '1.10');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add Vehicle'));
    await tester.pumpAndSettle();
    debugPrint('[E2E] vehicle submit settled');

    expect(
      find.text('Honda Activa 6G'),
      findsOneWidget,
      reason: 'saved vehicle should appear in the Vehicles tab',
    );
    expect(find.text('MH12AB1234'), findsOneWidget);
    debugPrint('[E2E] vehicle added');

    // ---------------------------------------------------------------
    // Logout user -> register Parking Owner
    // ---------------------------------------------------------------
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    debugPrint('[E2E] user logged out');
    // Logout awaits the async backend revoke before pushing the
    // role-selection route; pumpAndSettle can return mid-flight, so poll.
    for (
      var i = 0;
      i < 20 && find.text('What best describes you?').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
    expect(find.text('What best describes you?'), findsOneWidget);

    await tester.tap(find.text('Parking Owner'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Parking Owner Login'), findsOneWidget);

    final ownerCreate = find.text('Create Account');
    await tester.ensureVisible(ownerCreate);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(ownerCreate);
    await tester.pumpAndSettle();

    // Owners MUST supply a UPI id: it is the address users pay them at, so the
    // payment screen can offer UPI for this listing.
    final ownerReg = find.byType(TextFormField);
    expect(ownerReg, findsNWidgets(6));
    await tester.enterText(ownerReg.at(0), 'Test Owner');
    await tester.enterText(ownerReg.at(1), ownerEmail);
    await tester.enterText(ownerReg.at(2), '9876500142');
    await tester.enterText(ownerReg.at(3), 'e2eowner$stamp@okaxis');
    await tester.enterText(ownerReg.at(4), password);
    await tester.enterText(ownerReg.at(5), password);

    // Owners tick the same mandatory consent (rendered in owner green).
    await acceptTermsAndPrivacy(tester);

    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Continue'),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Hi, Test'),
      findsOneWidget,
      reason: 'owner lands on the Owner Dashboard',
    );
    debugPrint('[E2E] owner registered, dashboard shown');

    // ---------------------------------------------------------------
    // 2) Publish a parking (8-step wizard)
    // ---------------------------------------------------------------
    await tapTab(tester, 'Parkings');
    await tester.tap(find.text('Add Parking'));
    await tester.pumpAndSettle();

    // Step 1 — Photos (E2E picker returns the bundled asset)
    expect(find.text('Add photos of the parking space.'), findsOneWidget);
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 4 photos added.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 2 — Details (name + address).
    //
    // The address MUST geocode to a point within the app's nearby radius of
    // the E2E GPS fix (LocationService.e2ePoint = 19.0760, 72.8777, Kurla
    // West) because the user map looks for parkings around the DEVICE
    // position, not around the address. A made-up street in another locality
    // (the old "42 E2E Test Street, Bandra" resolved to Bandra West, 5.38 km
    // away) silently produced zero nearby markers. "Pipe Road, Kurla West"
    // was measured on-device at 19.0748, 72.8814 — 413 m away.
    await enterInStep(tester, DetailsStep, 0, parkingName);
    await enterInStep(
      tester,
      DetailsStep,
      1,
      'Pipe Road, Kurla West, Mumbai, Maharashtra 400070',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 3 — Location. The seed runs in a post-frame callback after a
    // platform-channel fix, so poll until the parking marker key appears
    // (the pinned-coordinate card was removed) before advancing (else Next
    // is gated on null coords).
    final seededIndex = find.byKey(const Key('owner-location-seeded'));
    var attempts = 0;
    while (seededIndex.evaluate().isEmpty && attempts < 100) {
      await tester.pump(const Duration(milliseconds: 250));
      attempts++;
    }
    if (seededIndex.evaluate().isEmpty) {
      final title = find
          .byType(AppBar)
          .evaluate()
          .map(
            (e) => (e.widget as AppBar).title is Text
                ? ((e.widget as AppBar).title as Text).data
                : null,
          )
          .whereType<String>()
          .toList();
      final visibleTexts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .toList();
      debugPrint('=== LOCSTEP DEBUG appbar: $title');
      debugPrint('=== LOCSTEP DEBUG visible texts: $visibleTexts');
      debugPrint(
        '=== LOCSTEP DEBUG locstep(onscreen)='
        '${find.byType(LocationStep).evaluate().length} '
        'locstep(all)='
        '${find.byType(LocationStep, skipOffstage: false).evaluate().length} '
        'dragHint(all)='
        '${find.textContaining('Drag the map', skipOffstage: false).evaluate().length}',
      );
    }
    expect(
      seededIndex,
      findsOneWidget,
      reason: 'Location step should auto-seed the emulator GPS fix',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 4 — Dimensions (plain numbers in metres)
    expect(
      find.text('Parking dimensions (metres)'),
      findsOneWidget,
      reason: 'expected to advance from Location onto the Dimensions step',
    );
    await enterInStep(tester, DimensionsStep, 0, '5.00');
    await enterInStep(tester, DimensionsStep, 1, '2.50');
    await enterInStep(tester, DimensionsStep, 2, '2.00');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 5 — Rental (Monthly on, rent ₹3,000)
    final rentalSwitches = find.descendant(
      of: find.byType(RentalStep),
      matching: find.byType(Switch),
    );
    await tester.tap(rentalSwitches.first);
    await tester.pumpAndSettle();
    await enterInStep(tester, RentalStep, 0, '3000');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 6 — Amenities (CCTV selected -> real DB row)
    await tester.tap(find.widgetWithText(FilterChip, 'CCTV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 7 — About (defaults: open, Both, auto-approval ON, 24/7)
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Step 8 — Review shows the REAL draft, then publish
    expect(find.text('Review your listing'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ReviewStep),
        matching: find.text(parkingName),
      ),
      findsOneWidget,
      reason: 'review must show the real parking name',
    );
    expect(
      find.descendant(
        of: find.byType(ReviewStep),
        matching: find.text('₹3,000'),
      ),
      findsOneWidget,
      reason: 'review must show the real monthly rent',
    );
    await tester.tap(find.text('Publish Parking'));
    await tester.pumpAndSettle();
    debugPrint('[E2E] parking published');

    // The publish snackbar can auto-dismiss during a long pumpAndSettle
    // (realtime upload + publish + dashboard refresh can exceed its 4s
    // window), so the authoritative proof of publish is the parking
    // appearing in the refreshed list below.
    expect(
      find.text(parkingName),
      findsOneWidget,
      reason: 'published parking should appear in the parkings list',
    );

    // Dashboard stats are real (computed by the provider from the API).
    await tapTab(tester, 'Dashboard');
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Occupied'), findsOneWidget);
    expect(
      find.text('₹0'),
      findsOneWidget,
      reason: 'fresh owner has no earnings yet',
    );

    // ---------------------------------------------------------------
    // Logout owner -> login Vehicle User -> map flow
    // ---------------------------------------------------------------
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    // Logout does an async backend revoke + secure-storage clear before the
    // role-selection route is pushed; pumpAndSettle can return while the
    // network call is still in flight, so poll for the role screen.
    for (
      var i = 0;
      i < 20 && find.text('Vehicle User').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
    expect(find.text('Vehicle User'), findsOneWidget);
    await tester.tap(find.text('Vehicle User'));
    await tester.pumpAndSettle();
    final userLogin = find.byType(TextFormField);
    await tester.enterText(userLogin.at(0), userEmail);
    await tester.enterText(userLogin.at(1), password);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hi, Test'), findsOneWidget);

    // ---------------------------------------------------------------
    // 3) Map: search -> real marker -> preview -> detail (fit check)
    // ---------------------------------------------------------------
    // Vehicles is the default tab now, so open the Map tab before touching
    // the search field: offstage widgets are skipped by the default finders.
    await tapTab(tester, 'Map');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Search bar works (geocoding may need extra wall-clock time). The query
    // must resolve far away from the emulator's own geo fix (Mumbai) and from
    // the parkings already in the database (Chennai), otherwise the searched
    // centre would still show the published parking and the empty-state
    // assertion below could not hold.
    await tester.enterText(find.byType(TextField), 'Kochi');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final suggestions = find.descendant(
      of: find.byType(UserMapTab),
      matching: find.byType(ListTile),
    );
    if (suggestions.evaluate().isNotEmpty) {
      await tester.tap(suggestions.first);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 900)); // pan debounce
      await tester.pumpAndSettle();

      // The geocoded "Kochi" centre lands ~1100 km from the published
      // parking, so the searched location overrides GPS until "Current
      // Location" and the map shows the REAL empty state.
      expect(
        find.text('No parking spaces available nearby'),
        findsOneWidget,
        reason: 'searched location overrides GPS until Current Location',
      );

      // "Current Location" restores the E2E GPS fix and the real marker
      // reappears.
      await tester.tap(find.byTooltip('Use current location'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 900)); // pan debounce
      await tester.pumpAndSettle();
    }

    // REAL markers from the backend (green P). Exactly our parking exists
    // after the DB cleanup, so at least one P always means real data.
    expect(
      find.descendant(of: find.byType(UserMapTab), matching: find.text('P')),
      findsWidgets,
      reason: 'map should show real parking markers',
    );

    // Open the preview card for a REAL parking (tap the marker's
    // GestureDetector by its stable key so the tap lands on its center).
    //
    // The database may hold more than one listing from earlier runs, so assert
    // against the name the preview card actually shows rather than assuming
    // this run's listing is the nearest one.
    await tester.tap(find.byKey(const Key('parking-marker')).first);
    await tester.pumpAndSettle();
    final previews = tester
        .widgetList<Text>(find.textContaining('E2E Greenview '))
        .map((t) => t.data)
        .whereType<String>()
        .where((d) => d.isNotEmpty)
        .toList();
    expect(
      previews,
      isNotEmpty,
      reason: 'preview card should show a real selected parking',
    );
    expect(
      previews.first,
      startsWith('E2E Greenview '),
      reason: 'the selected marker must be one of the published listings',
    );
    // Every listing in this run shares the wizard's dimensions and rent, so the
    // downstream fit-check / booking assertions hold for whichever one is
    // nearest the map centre.
    final selectedName = previews.first;
    debugPrint('[E2E] selected parking from the map: $selectedName');
    await tester.tap(find.text('View →'));
    await tester.pumpAndSettle();

    // Detail screen with the frontend fit check.
    expect(find.text('Parking details'), findsOneWidget);
    expect(find.text(selectedName), findsWidgets);
    expect(
      find.text('Perfect Fit'),
      findsOneWidget,
      reason: 'bike 1.80×0.70×1.10 vs 5.00×2.50×2.00 must be FIT',
    );
    expect(
      find.textContaining('5.00 × 2.50 × 2.00 m'),
      findsOneWidget,
      reason: 'dimensions must be plain numbers in metres',
    );
    await tester.tap(find.text('Book This Parking'));
    await tester.pumpAndSettle();

    // ---------------------------------------------------------------
    // 4) Book -> payment screen (UPI + Cash on Delivery only)
    // ---------------------------------------------------------------
    expect(find.text('Book Parking'), findsOneWidget);
    expect(
      find.text('Honda Activa 6G'),
      findsWidgets,
      reason: 'vehicle should be pre-selected',
    );
    expect(find.text('Monthly'), findsWidgets);
    await tester.tap(find.text('Submit Booking'));
    await tester.pumpAndSettle();

    // Amount comes from the server (auto-approved -> straight to payment).
    expect(find.text('Pay securely'), findsOneWidget);
    await waitForCta(tester, 'Pay Now ₹3,000');
    expect(
      find.text('₹3,000'),
      findsWidgets,
      reason: 'server-computed amount should be ₹3,000',
    );

    // The payment screen offers ONLY UPI and Cash on Delivery. Card and
    // NetBanking were removed.
    expect(find.text('Choose a payment method'), findsOneWidget);
    expect(find.text('UPI'), findsWidgets);
    expect(find.text('Cash on Delivery'), findsWidgets);
    expect(find.text('Card'), findsNothing);
    expect(find.text('NetBanking'), findsNothing);

    // The owner supplied a UPI id at sign-up, so UPI is offered and is the
    // DEFAULT selection (the call to action reads "Pay Now ₹3,000").
    expect(
      find.text('e2eowner$stamp@okaxis'),
      findsWidgets,
      reason: "the selected owner's own UPI id must be shown",
    );
    expect(find.text('PAYING THE PARKING OWNER'), findsOneWidget);
    expect(
      find.text('Pay Now ₹3,000'),
      findsOneWidget,
      reason: 'UPI must be preselected by default',
    );
    expect(
      find.text('Book on Cash · ₹3,000'),
      findsNothing,
      reason: 'Cash on Delivery must not be preselected',
    );

    // The booking is deliberately left UNPAID here: a pending payment still
    // holds the slot, which is what makes the overlapping attempt in step 5
    // conflict. It is settled with cash in step 6.
    await tester.pageBack(); // payment -> detail (the booking screen was replaced)
    await tester.pumpAndSettle();
    expect(find.text('Parking details'), findsOneWidget);
    await tester.pageBack(); // detail -> map
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Hi, Test'),
      findsOneWidget,
      reason: 'back on the user home shell',
    );

    // ---------------------------------------------------------------
    // 5) Overlap attempt -> backend 409, no second booking
    // ---------------------------------------------------------------
    // Leaving the pushed detail screen unmounted the home shell (an opaque
    // route hides everything below it), so the map tab is loading again:
    // poll until the real markers are back before tapping one.
    await tapTab(tester, 'Map');
    for (
      var i = 0;
      i < 40 && find.byKey(const Key('parking-marker')).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('parking-marker')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View →'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book This Parking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Booking'));
    await tester.pumpAndSettle();
    // The date conflict is surfaced as the professional "Parking Unavailable"
    // dialog (title + copy + [Change Dates] [OK]) — never as a technical
    // error, status code or stack trace. Whether it is caught by the read-only
    // availability pre-check or by the server's authoritative 409, the user
    // sees exactly this dialog.
    //
    // The same copy is ALSO kept on the form as an inline "Change Dates"
    // hint (that is the product design, not a duplicate), so the dialog
    // assertions are scoped to the AlertDialog.
    expect(
      find.text('Parking Unavailable'),
      findsOneWidget,
      reason: 'a conflicting window must raise the Parking Unavailable dialog',
    );
    final conflictDialog = find.byType(AlertDialog);
    expect(conflictDialog, findsOneWidget);
    expect(
      find.descendant(
        of: conflictDialog,
        matching: find.text(ErrorMessages.dateConflict),
      ),
      findsOneWidget,
      reason: 'the dialog must explain the conflict in plain language',
    );
    expect(
      find.descendant(of: conflictDialog, matching: find.text('Change Dates')),
      findsOneWidget,
      reason: 'the dialog offers to reopen the date picker',
    );
    expect(
      find.descendant(of: conflictDialog, matching: find.text('OK')),
      findsOneWidget,
      reason: 'the dialog can be dismissed',
    );
    for (final leaked in [
      'ApiException',
      'ApiErrorType.conflict',
      '409',
      '#0      ',
    ]) {
      expect(
        find.textContaining(leaked),
        findsNothing,
        reason: 'no technical detail may reach the user: $leaked',
      );
    }
    // [OK] just dismisses: no date picker, the screen stays on the booking
    // form with the inline conflict hint still shown. Regression guard — [OK]
    // used to be wired to the "reopen the date picker" branch, which silently
    // opened a date-picker dialog on top of the form.
    await tester.tap(
      find.descendant(of: conflictDialog, matching: find.text('OK')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Book Parking'), findsOneWidget);
    expect(find.text('Change Dates'), findsOneWidget);
    expect(
      find.byType(DatePickerDialog),
      findsNothing,
      reason: '[OK] must not open the date picker',
    );
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: '[OK] must leave no dialog behind',
    );

    // The inline "Change Dates" hint on the form re-opens the conflict
    // dialog, and the dialog's own [Change Dates] is what reopens the picker.
    // Regression guard — the two dialog actions used to be swapped, so [OK]
    // opened a date picker instead of [Change Dates].
    await tester.tap(find.text('Change Dates'));
    await tester.pumpAndSettle();
    expect(
      find.byType(AlertDialog),
      findsOneWidget,
      reason: 'the inline hint re-explains the conflict',
    );
    expect(find.text('Parking Unavailable'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Change Dates'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byType(DatePickerDialog),
      findsOneWidget,
      reason: '[Change Dates] must reopen the date picker',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Book Parking'), findsOneWidget);
    expect(
      find.byType(DatePickerDialog),
      findsNothing,
      reason: 'cancelling the picker returns to the booking form',
    );

    await tester.pageBack(); // booking -> detail
    await tester.pumpAndSettle();
    await tester.pageBack(); // detail -> map
    await tester.pumpAndSettle();

    // ---------------------------------------------------------------
    // 6) Pay with Cash on Delivery (an emulator has no UPI app)
    // ---------------------------------------------------------------
    // create() reloaded the user list, so the still-unpaid booking is here
    // with a "Pay" action that re-opens the payment screen.
    await tapTab(tester, 'Bookings');
    expect(find.text(selectedName), findsWidgets);
    expect(
      find.text('UPI'),
      findsWidgets,
      reason: 'an unpaid booking is still a UPI booking',
    );
    expect(
      find.text('Pay ₹3,000'),
      findsOneWidget,
      reason: 'an unpaid booking must offer Pay again',
    );
    await tester.tap(find.text('Pay ₹3,000'));
    await tester.pumpAndSettle();
    expect(find.text('Pay securely'), findsOneWidget);
    // The owner being paid is fetched for THIS parking, not remembered from a
    // previous screen, so the contact block is asserted before COD needs it.
    await waitForCta(tester, 'Pay Now ₹3,000');
    expect(
      find.text('Test Owner'),
      findsWidgets,
      reason: 'the payment screen names the owner being paid',
    );
    expect(
      find.text('e2eowner$stamp@okaxis'),
      findsWidgets,
      reason: "the selected owner's own UPI id must be shown",
    );

    await tester.tap(find.text('Cash on Delivery').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book on Cash · ₹3,000'));
    await tester.pumpAndSettle();

    // COD: no money has moved yet, so the screen hands the user over to the
    // owner (name, phone, address, optional UPI id) instead of confirming.
    expect(find.text('Please contact your parking owner'), findsOneWidget);
    expect(
      find.text('Test Owner'),
      findsWidgets,
      reason: 'the COD screen names the owner whose cash is expected',
    );
    expect(
      find.text('Amount to pay'),
      findsOneWidget,
      reason: 'COD still has an amount due to the owner',
    );
    expect(
      find.text('COD Pending'),
      findsOneWidget,
      reason: 'the COD screen shows the booking is not confirmed yet',
    );
    expect(
      find.textContaining('PSK-'),
      findsWidgets,
      reason: 'the booking reference is what the owner matches the cash to',
    );
    expect(
      find.textContaining('you can also pay by UPI'),
      findsWidgets,
      reason: "the owner's UPI id is offered as a fallback for the cash",
    );
    expect(
      find.text('Call owner'),
      findsOneWidget,
      reason: 'COD tells the user exactly how to reach the owner',
    );
    expect(
      find.text('Confirmed ✓'),
      findsNothing,
      reason: 'COD is not confirmed until the owner says so',
    );
    // Done lives below the fold of the scrolling COD screen.
    await scrollTo(tester, find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Hi, Test'),
      findsOneWidget,
      reason: 'Done returns to the user home',
    );

    // Bookings tab shows the pending-cash booking, not a confirmed one.
    await tapTab(tester, 'Bookings');
    expect(find.text(selectedName), findsWidgets);
    expect(
      find.text('Cash on Delivery'),
      findsWidgets,
      reason: 'the booking records the chosen method',
    );
    expect(find.text('COD Pending'), findsWidgets);
    expect(find.text('Contact owner to pay cash'), findsOneWidget);
    expect(
      find.text('Confirmed ✓'),
      findsNothing,
      reason: 'a COD_PENDING booking must not read as confirmed',
    );

    // ---------------------------------------------------------------
    // 7) Logout user -> login owner -> COD confirmation
    // ---------------------------------------------------------------
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    // Same async-logout race as the owner logout above: poll until the
    // role-selection screen is actually on stage.
    for (
      var i = 0;
      i < 20 && find.text('Parking Owner').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
    expect(find.text('Parking Owner'), findsOneWidget);
    await tester.tap(find.text('Parking Owner'));
    await tester.pumpAndSettle();
    final ownerLogin = find.byType(TextFormField);
    await tester.enterText(ownerLogin.at(0), ownerEmail);
    await tester.enterText(ownerLogin.at(1), password);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hi, Test'), findsOneWidget);

    // Owner bookings: real joined data (user + parking + vehicle + payment).
    await tapTab(tester, 'Bookings');
    expect(
      find.text('Test Driver'),
      findsWidgets,
      reason: 'booking card shows the real customer name',
    );
    expect(
      find.textContaining(selectedName),
      findsWidgets,
      reason: 'booking card shows the real parking name',
    );
    expect(
      find.textContaining('MH12AB1234'),
      findsWidgets,
      reason: 'booking card shows the real vehicle registration',
    );

    // The cash booking must read as unpaid: method chip + money-state chip,
    // and the action the owner needs to take.
    expect(find.text('Cash on Delivery'), findsWidgets);
    expect(find.text('COD Pending'), findsWidgets);
    expect(
      find.byKey(const Key('mark-cod-received-button')),
      findsOneWidget,
      reason: 'the owner is told to collect the cash',
    );
    expect(
      find.text('Confirmed'),
      findsNothing,
      reason: 'a pending cash booking is not confirmed yet',
    );
    expect(
      find.text('COD Paid'),
      findsNothing,
      reason: 'cash is only marked paid after the owner confirms it',
    );

    // Dashboard before the owner confirms: pending cash is worth NOTHING.
    await tapTab(tester, 'Dashboard');
    // The tab itself never reloads (only init + Refresh do), and the list was
    // loaded at login, before this booking existed.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    // Refresh is a real round trip: poll until the booking is actually in the
    // dashboard's own list (loaded at login, before this booking existed).
    for (
      var i = 0;
      i < 40 && find.text('Test Driver').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
    expect(
      find.text('₹0'),
      findsOneWidget,
      reason: 'cash that has not been handed over is not earnings',
    );
    expect(
      statValue('COD Pending'),
      '1',
      reason: 'the owner sees one booking awaiting cash',
    );
    expect(
      statValue('Available'),
      '1',
      reason: 'a pending cash booking must NOT block the slot',
    );
    expect(
      statValue('Occupied'),
      '0',
      reason: 'the parking is not occupied until the owner confirms',
    );
    expect(
      find.text('COD Paid'),
      findsNothing,
      reason: 'nothing is marked paid before the confirmation',
    );
    expect(
      find.text('Test Driver'),
      findsWidgets,
      reason: 'recent bookings row shows the real customer',
    );

    // The recent-booking row shows exactly ONE payment-method badge and ONE
    // status element, and that status element is the actionable "COD Pending"
    // pill (green once collected). It carries its own key so the Bookings-tab
    // button stays unambiguous while both tabs are alive in the IndexedStack.
    expect(
      find.byKey(const Key('dashboard-mark-cod-received-button')),
      findsOneWidget,
      reason: 'the dashboard row exposes the COD action',
    );
    expect(
      find.descendant(
        of: find.byType(OwnerDashboardScreen),
        matching: find.text('Cash on Delivery'),
      ),
      findsOneWidget,
      reason: 'one payment-method badge per recent-booking row',
    );
    expect(
      find.descendant(
        of: find.byType(OwnerDashboardScreen),
        matching: find.text('COD Pending'),
      ),
      findsNWidgets(2),
      reason: 'the COD Pending stat tile plus the single row status element',
    );

    // The single COD gate: Mark COD Received -> explicit confirmation.
    await tapTab(tester, 'Bookings');
    await tester.tap(find.byKey(const Key('mark-cod-received-button')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Confirm cash received?'),
      findsOneWidget,
      reason: 'collecting cash must be confirmed explicitly',
    );
    expect(
      find.textContaining('adds the amount to your earnings'),
      findsOneWidget,
      reason: 'the dialog spells out what confirming does',
    );
    expect(
      find.textContaining('PSK-'),
      findsOneWidget,
      reason: 'the dialog shows the reference to match the cash against',
    );
    expect(
      find.text('Cancel'),
      findsOneWidget,
      reason: 'collecting cash can be backed out of',
    );
    await tester.tap(find.byKey(const Key('confirm-cod-dialog-yes')));
    // confirmCod is a network round trip, so poll until the owner action is
    // gone (i.e. the booking is no longer awaiting cash).
    for (
      var i = 0;
      i < 40 &&
          find.byKey(const Key('mark-cod-received-button')).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();

    expect(
      find.text('COD Paid'),
      findsWidgets,
      reason: 'confirming the cash marks the payment COD Paid',
    );
    expect(
      find.text('Confirmed'),
      findsWidgets,
      reason: 'confirming the cash confirms the booking',
    );
    expect(
      find.text('COD Pending'),
      findsNothing,
      reason: 'the booking is no longer awaiting cash',
    );
    expect(
      find.byKey(const Key('mark-cod-received-button')),
      findsNothing,
      reason: 'the collect-cash action is spent',
    );

    // Detail sheet with Call / Message / View Details.
    await tester.tap(find.text('Test Driver'));
    await tester.pumpAndSettle();
    expect(find.text('Booking Details'), findsOneWidget);
    expect(find.text('CUSTOMER'), findsOneWidget);

    // Payment section is below the fold in the sheet — scroll to it.
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('PSK-'),
      findsWidgets,
      reason: 'sheet shows the real payment reference',
    );
    expect(find.text('Cash on Delivery'), findsWidgets);
    expect(find.text('COD Paid'), findsWidgets);
    expect(
      find.text('Cash received'),
      findsOneWidget,
      reason: 'the sheet records when the owner took the cash',
    );
    expect(
      find.text('Receipt ID'),
      findsOneWidget,
      reason: 'cash shows its collected-cash receipt id',
    );
    expect(
      find.text('Txn ID'),
      findsNothing,
      reason: 'cash has no UPI transaction id',
    );
    expect(
      find.text('e2eowner$stamp@okaxis'),
      findsWidgets,
      reason: 'the sheet shows the owner UPI id used for this booking',
    );

    // Message -> real conversation -> send a message. The sheet is scoped
    // explicitly: the booking card behind it has its own chat button.
    final detailSheet = find.byType(OwnerBookingDetailSheet);
    expect(detailSheet, findsOneWidget);
    expect(
      find.descendant(
        of: detailSheet,
        matching: find.byIcon(Icons.phone_outlined),
      ),
      findsOneWidget,
      reason: 'the sheet offers a Call action for the user',
    );
    final messageButton = find.descendant(
      of: detailSheet,
      matching: find.byIcon(Icons.chat_bubble_outline),
    );
    expect(messageButton, findsOneWidget);
    await tester.ensureVisible(messageButton);
    await tester.pumpAndSettle();
    await tester.tap(messageButton);
    await tester.pumpAndSettle();
    expect(
      find.text('Test Driver'),
      findsWidgets,
      reason: 'chat should be titled with the customer name',
    );
    // Chat _init loads the (real) conversation over HTTP; pumpAndSettle can
    // return while it is in flight, so poll until the loading spinner goes.
    for (
      var i = 0;
      i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'Please share the entry code',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send)); // send
    await tester.pumpAndSettle();
    expect(
      find.text('Please share the entry code'),
      findsOneWidget,
      reason: 'sent message must appear as a chat bubble',
    );

    await tester.pageBack(); // chat -> dashboard
    await tester.pumpAndSettle();

    // Owner Inbox shows the real conversation.
    await tapTab(tester, 'Inbox');
    expect(
      find.text('Test Driver'),
      findsWidgets,
      reason: 'owner inbox should list the conversation with the user',
    );

    // ---------------------------------------------------------------
    // 8) Owner dashboard: earnings appear the moment the cash is confirmed
    // ---------------------------------------------------------------
    // No refresh here on purpose: confirmCod reloads the stats itself, so the
    // earnings must already include the collected cash. Poll until that
    // reload has landed.
    await tapTab(tester, 'Dashboard');
    for (
      var i = 0;
      i < 40 && find.text('COD Paid').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
    expect(
      find.text('₹3,000'),
      findsWidgets,
      reason: 'confirmed cash must be counted in total earnings',
    );
    expect(
      find.text('1 paid booking · pending cash not included'),
      findsOneWidget,
      reason: 'earnings count only money that actually arrived',
    );
    expect(
      statValue('COD Pending'),
      '0',
      reason: 'the owner has no cash left to collect',
    );
    expect(
      statValue('Occupied'),
      '1',
      reason: 'a confirmed booking makes the parking Occupied',
    );
    expect(
      statValue('Available'),
      '0',
      reason: 'the confirmed booking now holds the slot',
    );
    expect(
      find.text('COD Paid'),
      findsWidgets,
      reason: 'the recent-booking row shows the settled payment',
    );
    expect(
      find.text('Confirmed'),
      findsWidgets,
      reason: 'the recent-booking row shows the confirmed booking',
    );
    expect(
      find.text('Test Driver'),
      findsWidgets,
      reason: 'recent bookings row shows the real customer',
    );
    expect(
      find.byKey(const Key('dashboard-mark-cod-received-button')),
      findsNothing,
      reason: 'the collected cash is no longer actionable on the dashboard',
    );
    expect(
      find.descendant(
        of: find.byType(OwnerDashboardScreen),
        matching: find.text('COD Pending'),
      ),
      findsOneWidget,
      reason: 'only the COD Pending stat tile is left, never a second badge',
    );
  }, timeout: const Timeout(Duration(minutes: 12)));
}
