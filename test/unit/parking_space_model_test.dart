import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/shared/models/parking_space.dart';

/// The slot/pool/availability models are what every "is it free?" line in the
/// app is built from, so they get their own coverage.
void main() {
  group('ParkingSpaceVehicleType', () {
    test('label maps each type to its own name', () {
      // This was inverted (car -> "Bike"), which mislabelled every car slot in
      // the Spaces step: tab titles, the Add button and the card headings.
      expect(ParkingSpaceVehicleType.label(ParkingSpaceVehicleType.car), 'Car');
      expect(
        ParkingSpaceVehicleType.label(ParkingSpaceVehicleType.bike),
        'Bike',
      );
    });

    test(
      'every declared type has a label, and the list is the two of them',
      () {
        expect(ParkingSpaceVehicleType.all, ['BIKE', 'CAR']);
        for (final t in ParkingSpaceVehicleType.all) {
          expect(
            ParkingSpaceVehicleType.label(t),
            isNotEmpty,
            reason: '$t must have UI copy',
          );
        }
      },
    );
  });

  group('ParkingSpace', () {
    test('isCar / isBike are mutually exclusive', () {
      final car = ParkingSpace.draft(
        spaceCode: 'C1',
        vehicleType: ParkingSpaceVehicleType.car,
      );
      final bike = ParkingSpace.draft(
        spaceCode: 'B1',
        vehicleType: ParkingSpaceVehicleType.bike,
      );
      expect(car.isCar, isTrue);
      expect(car.isBike, isFalse);
      expect(bike.isBike, isTrue);
      expect(bike.isCar, isFalse);
    });

    test('displayLabel prefers the owner name and falls back to the code', () {
      ParkingSpace at(String? name) => ParkingSpace.draft(
        spaceCode: 'C1',
        spaceName: name,
        vehicleType: ParkingSpaceVehicleType.car,
      );
      expect(at('Corner slot').displayLabel, 'Corner slot');
      expect(at('   ').displayLabel, 'C1');
      expect(at(null).displayLabel, 'C1');
    });

    test('dimensionLabel is an em dash until a real size is known', () {
      ParkingSpace sized({double? l, double? w}) => ParkingSpace.draft(
        spaceCode: 'C1',
        vehicleType: ParkingSpaceVehicleType.car,
        lengthM: l,
        widthM: w,
      );
      expect(sized().dimensionLabel, '—');
      expect(sized(l: 5).dimensionLabel, '—', reason: 'half a size is no size');
      expect(
        sized(l: 5, w: 2.5).dimensionLabel,
        '8.20 ft × 16.40 ft',
        reason: 'labels are shown in feet; the model stores metres',
      );
    });

    test('fromJson round-trips the server row, including the per-date flag', () {
      final s = ParkingSpace.fromJson({
        'id': 'sp-1',
        'parkingId': 'p-1',
        'spaceCode': 'C2',
        'spaceName': 'Corner',
        'vehicleType': 'CAR',
        'lengthM': 5,
        'widthM': '2.5',
        'heightM': 2.2,
        'isActive': true,
        'available': false,
      });
      expect(s.id, 'sp-1');
      expect(s.spaceCode, 'C2');
      expect(s.isCar, isTrue);
      expect(s.lengthM, 5.0);
      expect(s.widthM, 2.5);
      expect(s.available, isFalse);
      // Absent flag means "the server did not evaluate it", not "unavailable".
      expect(ParkingSpace.fromJson({'id': 'x'}).available, isNull);
    });

    test('booked is date-only, so "Booked" is never a guess', () {
      // The detail screen greys a slot out for either reason. Only a slot the
      // server says is occupied may be labelled "Booked"; one that is merely
      // too small / behind a tight gate has to read "Unavailable", otherwise the
      // app invents a booking that does not exist.
      final taken = ParkingSpace.fromJson({
        'spaceCode': 'C1',
        'available': false,
        'booked': true,
      });
      expect(taken.available, isFalse);
      expect(taken.booked, isTrue);

      final tooSmall = ParkingSpace.fromJson({
        'spaceCode': 'C2',
        'available': false,
        'booked': false,
      });
      expect(tooSmall.booked, isFalse);

      // A free slot is never "booked", and a missing flag stays unknown.
      expect(
        ParkingSpace.fromJson({'spaceCode': 'C3', 'available': true}).booked,
        isNull,
      );
      expect(ParkingSpace.fromJson({'spaceCode': 'C4'}).booked, isNull);
    });

    test('toPayload sends a trimmed name, or null for a blank one', () {
      ParkingSpace named(String? n) => ParkingSpace.draft(
        spaceCode: 'C1',
        spaceName: n,
        vehicleType: ParkingSpaceVehicleType.car,
        lengthM: 5,
        widthM: 2.5,
        heightM: 2.2,
      );
      expect(named('  Near gate  ').toPayload()['spaceName'], 'Near gate');
      expect(named('   ').toPayload()['spaceName'], isNull);
      expect(named(null).toPayload()['spaceName'], isNull);
    });
  });

  group('ParkingSpacePool', () {
    test('isEmpty, isFull and hasFree all need a real total', () {
      expect(const ParkingSpacePool().isEmpty, isTrue);
      // Zero of zero is "no pool at all", never "full".
      expect(const ParkingSpacePool().isFull, isFalse);
      expect(const ParkingSpacePool(total: 2, available: 0).isFull, isTrue);
      expect(const ParkingSpacePool(total: 2, available: 0).isEmpty, isFalse);
      expect(const ParkingSpacePool(total: 2, available: 1).hasFree, isTrue);
    });

    test('reads numbers whether the API sent ints or strings', () {
      final p = ParkingSpacePool.fromJson({'total': '3', 'available': 2});
      expect(p.total, 3);
      expect(p.available, 2);
      expect(ParkingSpacePool.fromJson(null).total, 0);
    });
  });

  group('ParkingAvailability', () {
    ParkingAvailability build({
      String? vehicleType = ParkingSpaceVehicleType.car,
      int total = 2,
      int available = 1,
      bool fitsAnySpace = true,
      bool legacyParkingBlocked = false,
      ParkingSpacePool carSpaces = const ParkingSpacePool(),
      ParkingSpacePool bikeSpaces = const ParkingSpacePool(),
    }) => ParkingAvailability(
      parkingId: 'p-1',
      vehicleType: vehicleType,
      totalSpaces: total,
      availableSpaces: available,
      fitsAnySpace: fitsAnySpace,
      legacyParkingBlocked: legacyParkingBlocked,
      carSpaces: carSpaces,
      bikeSpaces: bikeSpaces,
    );

    test('has a verdict only when the server was given a vehicle', () {
      expect(build().hasVerdict, isTrue);
      expect(build(vehicleType: null).hasVerdict, isFalse);
      // No vehicle -> no verdict -> never "full", which would block the screen
      // on a number nobody asked for.
      expect(build(vehicleType: null, available: 0).isFullForVehicle, isFalse);
      expect(build(available: 0).isFullForVehicle, isTrue);
      // Nothing of that type at all is not "full", it is "not offered".
      expect(build(total: 0, available: 0).isFullForVehicle, isFalse);
    });

    test('statusLine separates full, too-small and not-offered', () {
      expect(build(available: 0).statusLine, 'Car Parking Full');
      expect(
        build(available: 0, fitsAnySpace: false).statusLine,
        'Your vehicle may not fit this parking space.',
      );
      expect(
        build(total: 0).statusLine,
        'No Car parking spaces in this parking.',
      );
      expect(
        build(total: 0, legacyParkingBlocked: true).statusLine,
        'No Car spaces available for these dates.',
      );
    });

    test('statusLine counts in words, never inventing a count', () {
      expect(build(available: 1).statusLine, '1 Car space available');
      expect(build(available: 3).statusLine, '3 Car spaces available');
      expect(
        build(
          vehicleType: ParkingSpaceVehicleType.bike,
          available: 2,
        ).statusLine,
        '2 Bike spaces available',
      );
    });

    test('with no vehicle it falls back to the per-type pools', () {
      const car = ParkingSpacePool(total: 2, available: 1);
      const bike = ParkingSpacePool(total: 3, available: 0);
      expect(
        build(vehicleType: null, carSpaces: car, bikeSpaces: bike).statusLine,
        'Spaces free: 1/2 car · 0/3 bike',
      );
      expect(
        build(vehicleType: null).statusLine,
        'Parking space details unavailable.',
      );
    });
  });
}
