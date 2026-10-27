import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/core/services/photo_picker_service.dart';
import 'package:parkshare_new/modules/owner/add_parking/parking_draft.dart';
import 'package:parkshare_new/shared/models/parking_space.dart';

PickedPhoto _photo() => PickedPhoto(
  bytes: Uint8List.fromList(const [137, 80, 78, 71]),
  filename: 'parking_photo.png',
  contentType: 'image/png',
);

/// A draft that passes every publish rule, so each test can break exactly one
/// thing and assert on the specific message it expects.
///
/// A slot is NEVER back-filled from the plot or the gate, so the fixture types
/// the bay's own size the way the wizard asks the owner to.
ParkingDraft _completeDraft() {
  final draft = ParkingDraft()
    ..photos.add(_photo())
    ..parkingName = 'Greenview Secure Parking'
    ..address = 'MG Road'
    ..latitude = 19.076
    ..longitude = 72.8777
    ..lengthM = 5
    ..widthM = 2.5
    ..heightM = 2
    ..entranceWidthM = 2.5
    ..entranceHeightM = 2
    ..carMonthlyEnabled = true
    ..carMonthlyRent = 3500
    ..setCapacity(ParkingSpaceVehicleType.car, 1);
  draft.spaces[0] = draft.spaces[0].copyWith(
    lengthM: 5,
    widthM: 2.5,
    heightM: 2,
  );
  return draft;
}

void main() {
  group('ParkingDraft publish validation', () {
    test(
      'requires photos, name, address, location, dims, gate, spaces, rent',
      () {
        final draft = ParkingDraft();
        expect(draft.validateForPublish(), 'Add at least one photo.');

        draft.photos.add(_photo());
        expect(draft.validateForPublish(), 'Enter a parking name.');

        draft.parkingName = 'Greenview';
        expect(draft.validateForPublish(), 'Enter the address.');

        draft.address = 'MG Road';
        expect(
          draft.validateForPublish(),
          'Pick the parking location on the map.',
        );

        draft
          ..latitude = 19.0760
          ..longitude = 72.8777;
        expect(
          draft.validateForPublish(),
          'Enter parking length, width and height.',
        );

        draft
          ..lengthM = 5
          ..widthM = 2.5
          ..heightM = 2;
        expect(
          draft.validateForPublish(),
          'Enter the entrance (gate) width — it decides what can get in.',
        );

        draft.entranceWidthM = 2.5;
        expect(
          draft.validateForPublish(),
          'Enter the entrance (gate) height — it decides what can get in.',
        );

        draft.entranceHeightM = 2;
        expect(
          draft.validateForPublish(),
          'Add at least one parking space (car or bike).',
        );

        // No slots yet -> the space step blocks, before rental is even reached.
        draft.setCapacity(ParkingSpaceVehicleType.car, 1);
        expect(
          draft.validateForPublish(),
          'Enter the dimensions for Car Space 1.',
          reason: 'a new slot is empty until the owner measures the bay',
        );
        draft.spaces[0] = draft.spaces[0].copyWith(
          lengthM: 5,
          widthM: 2.5,
          heightM: 2,
        );
        expect(
          draft.validateForPublish(),
          'Enable at least one rental plan (car and/or bike).',
        );

        draft.carMonthlyEnabled = true;
        draft.carMonthlyRent = 3000;
        expect(draft.validateForPublish(), isNull);
      },
    );

    test('rent > 0 required when a plan is enabled', () {
      final draft = _completeDraft()
        ..carYearlyEnabled = true
        ..carYearlyRent = 0;
      expect(
        draft.validateForPublish(),
        'Car yearly rent must be greater than 0.',
      );
    });

    test('at least one plan must be enabled', () {
      final draft = _completeDraft()
        ..carMonthlyEnabled = false
        ..carMonthlyRent = null;
      expect(
        draft.validateForPublish(),
        'Enable at least one rental plan (car and/or bike).',
      );
    });

    test('a listing with no parking spaces is never publishable', () {
      final draft = _completeDraft();
      expect(draft.spacesError, isNull);
      expect(draft.validateForPublish(), isNull);

      draft.spaces.clear();
      draft.syncCapacityCounters();
      expect(
        draft.validateForPublish(),
        'Add at least one parking space (car or bike).',
      );
    });
  });

  group('ParkingDraft.toPayload', () {
    test(
      'plain number metres, photos, amenities — and NO amount (server-side)',
      () {
        final draft = ParkingDraft()
          ..parkingName = 'Greenview Secure Parking'
          ..address = 'MG Road'
          ..city = 'Mumbai'
          ..latitude = 19.076
          ..longitude = 72.8777
          ..lengthM = 5.00
          ..widthM = 2.50
          ..heightM = 2.00
          ..carMonthlyEnabled = true
          ..carMonthlyRent = 3500
          ..carYearlyEnabled = true
          ..carYearlyRent = 35000
          ..bikeMonthlyEnabled = true
          ..bikeMonthlyRent = 2000
          ..bikeYearlyEnabled = false
          ..bikeYearlyRent = 25000
          ..amenities.addAll(['CCTV', 'Security']);

        // vehicleType is DERIVED from the real slots, never set by hand.
        draft
          ..spaces.add(
            ParkingSpace.draft(
              spaceCode: 'C1',
              vehicleType: ParkingSpaceVehicleType.car,
              lengthM: 5,
              widthM: 2.5,
              heightM: 2,
            ),
          )
          ..spaces.add(
            ParkingSpace.draft(
              spaceCode: 'B1',
              vehicleType: ParkingSpaceVehicleType.bike,
              lengthM: 2.5,
              widthM: 1,
              heightM: 2,
            ),
          );
        expect(draft.vehicleType, 'BOTH');

        final payload = draft.toPayload([
          'http://localhost:8080/uploads/a.png',
        ]);

        expect(payload['lengthM'], 5.00);
        expect(payload['widthM'], 2.50);
        expect(payload['heightM'], 2.00);
        // The four independent per-vehicle plans.
        expect(payload['carMonthlyEnabled'], true);
        expect(payload['carMonthlyRent'], 3500);
        expect(payload['carYearlyEnabled'], true);
        expect(payload['carYearlyRent'], 35000);
        expect(payload['bikeMonthlyEnabled'], true);
        expect(payload['bikeMonthlyRent'], 2000);
        expect(payload['bikeYearlyEnabled'], false);
        expect(
          payload['bikeYearlyRent'],
          isNull,
          reason: 'a disabled plan never carries a price',
        );
        // The legacy monthly/yearly pair is DERIVED (car first) so older
        // readers keep working.
        expect(payload['monthlyEnabled'], true);
        expect(payload['monthlyRent'], 3500);
        expect(payload['yearlyEnabled'], true);
        expect(payload['yearlyRent'], 35000);
        expect(payload['amenities'], containsAll(['CCTV', 'Security']));
        expect(payload['photoUrls'], ['http://localhost:8080/uploads/a.png']);
        expect(payload['maximumCars'], 1); // derived from the slot rows
        expect(payload['maximumBikes'], 1);
        expect((payload['spaces'] as List).length, 2);
        expect(payload.containsKey('amount'), isFalse); // server computes
      },
    );

    test('unused plans send null rent', () {
      final draft = ParkingDraft()
        ..carMonthlyEnabled = true
        ..carMonthlyRent = 100
        ..bikeYearlyEnabled = false
        ..bikeYearlyRent = 9999;
      final payload = draft.toPayload([]);
      expect(payload['carMonthlyRent'], 100);
      expect(payload['bikeYearlyRent'], isNull);
      // Derived legacy pair follows the enabled plans (car first here).
      expect(payload['monthlyRent'], 100);
      expect(payload['yearlyRent'], isNull);
    });
  });

  group('ParkingDraft slot capacity', () {
    ParkingDraft build() => ParkingDraft()
      ..lengthM = 5
      ..widthM = 2.5
      ..heightM = 2;

    test('setCapacity grows rows and re-syncs the stepper counters', () {
      final d = build()..setCapacity(ParkingSpaceVehicleType.car, 3);
      expect(d.carSpaceCount, 3);
      expect(d.maximumCars, 3, reason: 'counter must follow the real rows');
      expect(d.carSpaces.map((s) => s.spaceCode).toList(), [
        'C1',
        'C2',
        'C3',
      ], reason: 'codes are sequential and collision-free');
      expect(d.vehicleType, 'CAR');
    });

    test('shrinking keeps custom rows and leaves no gap in the codes', () {
      final d = build()..setCapacity(ParkingSpaceVehicleType.car, 4);
      // Owner names the 2nd space (mutate the real list, like _SpaceCard does).
      d.spaces[1] = d.spaces[1].copyWith(spaceName: 'Near gate');
      d.setCapacity(ParkingSpaceVehicleType.car, 3);
      expect(d.carSpaceCount, 3);
      expect(d.carSpaces.map((s) => s.spaceCode).toList(), ['C1', 'C2', 'C3']);
      expect(
        d.spaces.any((s) => s.spaceName == 'Near gate'),
        isTrue,
        reason: 'rows the owner customised must survive a resize',
      );
    });

    test(
      'a new slot is empty, never back-filled from the plot or the gate',
      () {
        // The plot (5 x 2.5) and the gate are a different concept from one
        // physical bay, so a slot starts blank and the owner measures it. A car
        // plot must never be handed out as a bike slot, either.
        final d = build()..setCapacity(ParkingSpaceVehicleType.bike, 2);
        for (final s in d.bikeSpaces) {
          expect(s.lengthM, isNull);
          expect(s.widthM, isNull);
          expect(s.heightM, isNull);
        }
        expect(d.spacesError, 'Enter the dimensions for Bike Space 1.');
      },
    );

    test('car + bike slots derive BOTH, and the payload mirrors the rows', () {
      final d = build()
        ..setCapacity(ParkingSpaceVehicleType.car, 2)
        ..setCapacity(ParkingSpaceVehicleType.bike, 3);
      expect(d.vehicleType, 'BOTH');
      expect(d.offersType('CAR'), isTrue);
      expect(d.offersType('BIKE'), isTrue);
      final payload = d.toPayload([]);
      expect(payload['maximumCars'], 2);
      expect(payload['maximumBikes'], 3);
      expect(payload['vehicleType'], 'BOTH');
      expect((payload['spaces'] as List).length, 5);
    });

    test('removing every car row leaves a bike-only listing', () {
      final d = build()
        ..setCapacity(ParkingSpaceVehicleType.car, 2)
        ..setCapacity(ParkingSpaceVehicleType.bike, 1);
      d.setCapacity(ParkingSpaceVehicleType.car, 0);
      expect(d.carSpaceCount, 0);
      expect(d.vehicleType, 'BIKE');
      expect(d.offersType('CAR'), isFalse);
    });

    test('duplicate codes and missing sizes are rejected before publish', () {
      final d = build()..setCapacity(ParkingSpaceVehicleType.car, 2);
      // Size both bays the way the wizard asks, then break one rule at a time.
      for (var i = 0; i < d.spaces.length; i++) {
        d.spaces[i] = d.spaces[i].copyWith(lengthM: 5, widthM: 2.5, heightM: 2);
      }
      expect(d.spacesError, isNull);

      d.spaces[0] = d.spaces[0].copyWith(spaceCode: 'C2');
      expect(d.spacesError, 'Parking space codes must be unique.');

      d.spaces[0] = d.spaces[0].copyWith(spaceCode: 'C1', widthM: 0);
      // The message names the row the owner has to fix, in slot language.
      expect(d.spacesError, 'Enter the dimensions for Car Space 1.');
    });

    test('a listing with no slots at all cannot be published', () {
      final d = build();
      expect(d.spacesError, 'Add at least one parking space (car or bike).');
    });
  });
}
