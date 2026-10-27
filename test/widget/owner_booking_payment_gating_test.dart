// Widget tests for the owner booking detail sheet's payment actions.
//
// The owner UI must never offer a manual UPI confirmation and must never expose
// the owner's personal UPI id. Online (Razorpay) payments are verified by the
// gateway, and the legacy direct-UPI "Verify UPI Payment" action has been
// removed from the active owner UI entirely. COD keeps its
// "Mark COD Received" action untouched.
//
// The sheet builds from the Booking value alone (no providers required to
// render), so these tests mount it directly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/modules/owner/bookings/owner_booking_detail_sheet.dart';
import 'package:parkshare_new/shared/models/booking.dart';

Map<String, dynamic> _bookingJson({
  required String method,
  required String paymentStatus,
  required String status,
}) => {
  'bookingId': 'b_1',
  'parkingId': 'p_1',
  'userId': 'u_1',
  'ownerId': 'o_1',
  'vehicleId': 'v_1',
  'amount': 500,
  'status': status,
  'createdAt': '2024-01-01T00:00:00.000Z',
  'updatedAt': '2024-01-01T00:00:00.000Z',
  'paymentMethod': method,
  'paymentStatus': paymentStatus,
  'user': {'id': 'u_1', 'name': 'Ravi', 'phone': '9876543210'},
  'owner': {'id': 'o_1', 'name': 'Owner A', 'upiId': 'owner@upi'},
  'parking': {'name': 'Sunrise', 'address': '1 Main Road'},
  'vehicle': {
    'type': 'CAR',
    'brand': 'Maruti',
    'model': 'Swift',
    'registrationNumber': 'TN01AB1234',
  },
};

Future<void> _pumpSheet(WidgetTester tester, Map<String, dynamic> json) async {
  // A tall viewport so the lazily-built ListView renders the whole sheet,
  // including the Payment section that holds the actions under test.
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: OwnerBookingDetailSheet(booking: Booking.fromJson(json)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Razorpay booking shows no Verify UPI and no owner UPI id', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      _bookingJson(
        method: 'RAZORPAY',
        paymentStatus: 'SUCCESS',
        status: BookingStatus.confirmed,
      ),
    );

    expect(find.byKey(const Key('verify-upi-payment-button')), findsNothing);
    expect(find.text('Verify UPI Payment'), findsNothing);
    // The owner's personal UPI id must never be rendered for a Razorpay booking.
    expect(find.text('owner@upi'), findsNothing);
    // Verification is attributed to the gateway, not the owner.
    expect(find.text('Verified by Razorpay'), findsOneWidget);
    expect(find.text('Online Payment'), findsOneWidget);
    // No COD action on a confirmed online booking.
    expect(find.byKey(const Key('mark-cod-received-button')), findsNothing);
  });

  testWidgets('legacy direct-UPI booking no longer offers a manual Verify UPI', (
    tester,
  ) async {
    await _pumpSheet(
      tester,
      _bookingJson(
        method: 'UPI',
        paymentStatus: 'UPI_PENDING_VERIFICATION',
        status: BookingStatus.paymentPending,
      ),
    );

    // The old owner UPI/manual-verification flow has been removed from the UI.
    expect(find.byKey(const Key('verify-upi-payment-button')), findsNothing);
    expect(find.text('Verify UPI Payment'), findsNothing);
    expect(find.text('I have the money'), findsNothing);
    // The owner's personal UPI id is never shown in the owner UI.
    expect(find.text('owner@upi'), findsNothing);
    expect(find.text('Verified by Razorpay'), findsNothing);
  });

  testWidgets('COD booking still offers Mark COD Received', (tester) async {
    await _pumpSheet(
      tester,
      _bookingJson(
        method: 'COD',
        paymentStatus: 'COD_PENDING',
        status: BookingStatus.codPending,
      ),
    );

    expect(find.byKey(const Key('mark-cod-received-button')), findsOneWidget);
    expect(find.byKey(const Key('verify-upi-payment-button')), findsNothing);
    expect(find.text('owner@upi'), findsNothing);
  });
}
