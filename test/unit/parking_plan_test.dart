import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/shared/models/parking.dart';

/// Locks the per-vehicle rental-plan resolution contract ([ParkingListing.planFor])
/// introduced by the car/bike × monthly/yearly pricing split:
///
///  * 'CAR'  -> the car plan only (falls back to the legacy pair if the
///    per-car fields were never saved).
///  * 'BIKE' -> the bike plan only.
///  * null / unknown -> the UNION of both types' plans, so screens that have
///    not picked a vehicle yet still offer every available plan.
ParkingListing _listing({
  bool carMonthlyEnabled = false,
  double? carMonthlyRent,
  bool carYearlyEnabled = false,
  double? carYearlyRent,
  bool bikeMonthlyEnabled = false,
  double? bikeMonthlyRent,
  bool bikeYearlyEnabled = false,
  double? bikeYearlyRent,
}) {
  return ParkingListing(
    id: 'p1',
    ownerId: 'o1',
    ownerName: 'Owner',
    parkingName: 'Greenview',
    address: 'MG Road',
    parkingType: ParkingType.nonCovered,
    vehicleType: 'BOTH',
    monthlyEnabled: carMonthlyEnabled || bikeMonthlyEnabled,
    yearlyEnabled: carYearlyEnabled || bikeYearlyEnabled,
    carMonthlyEnabled: carMonthlyEnabled,
    carMonthlyRent: carMonthlyRent,
    carYearlyEnabled: carYearlyEnabled,
    carYearlyRent: carYearlyRent,
    bikeMonthlyEnabled: bikeMonthlyEnabled,
    bikeMonthlyRent: bikeMonthlyRent,
    bikeYearlyEnabled: bikeYearlyEnabled,
    bikeYearlyRent: bikeYearlyRent,
  );
}

void main() {
  group('ParkingListing.planFor', () {
    test("'CAR' resolves the car plan on its own", () {
      final p = _listing(
        carMonthlyEnabled: true,
        carMonthlyRent: 3500,
        bikeMonthlyEnabled: true,
        bikeMonthlyRent: 9999,
      );
      final plan = p.planFor('CAR');
      expect(plan.monthlyEnabled, isTrue);
      expect(
        plan.monthlyRent,
        3500,
        reason: 'the car plan must not leak the bike monthly price',
      );
      expect(plan.yearlyEnabled, isFalse);
      expect(plan.yearlyRent, isNull);
    });

    test("'BIKE' resolves the bike plan on its own", () {
      final p = _listing(bikeYearlyEnabled: true, bikeYearlyRent: 25000);
      final plan = p.planFor('BIKE');
      expect(plan.monthlyEnabled, isFalse);
      expect(plan.yearlyEnabled, isTrue);
      expect(plan.yearlyRent, 25000);
    });

    test('a null vehicle type offers the UNION of both plans', () {
      final p = _listing(
        carMonthlyEnabled: true,
        carMonthlyRent: 3500,
        bikeYearlyEnabled: true,
        bikeYearlyRent: 25000,
      );
      final plan = p.planFor(null);
      expect(plan.monthlyEnabled, isTrue);
      expect(plan.monthlyRent, 3500);
      expect(plan.yearlyEnabled, isTrue);
      expect(plan.yearlyRent, 25000);
    });

    test('an unknown vehicle type cannot hide an available plan', () {
      final p = _listing(carMonthlyEnabled: true, carMonthlyRent: 1200);
      final plan = p.planFor('TRUCK');
      expect(plan.monthlyEnabled, isTrue);
      expect(plan.monthlyRent, 1200);
    });

    test(
      'legacy monthly/yearly pair still resolves when per-vehicle is absent',
      () {
        final p = _listing(); // all per-vehicle fields off
        final plan = p.planFor('CAR');
        expect(plan.anyEnabled, isFalse);
      },
    );
  });
}
