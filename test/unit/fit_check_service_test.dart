import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/core/services/fit_check_service.dart';

void main() {
  group('FitCheckService.check', () {
    // Parking 5.00 x 2.50 x 2.00, vehicle 4.00 x 1.80 x 1.50
    const pL = 5.00, pW = 2.50, pH = 2.00;
    const vL = 4.00, vW = 1.80, vH = 1.50;

    test('comfortable clearance => FIT', () {
      final result = FitCheckService.check(
        parkingLengthM: pL,
        parkingWidthM: pW,
        parkingHeightM: pH,
        vehicleLengthM: vL,
        vehicleWidthM: vW,
        vehicleHeightM: vH,
      );
      expect(result, FitResult.fit);
      expect(FitCheckService.wire(result), 'FIT');
    });

    test('clearance shorter than +0.50 m but still fits => TIGHT_FIT', () {
      // Length clearance 0.49 < 0.50
      final result = FitCheckService.check(
        parkingLengthM: 4.49,
        parkingWidthM: pW,
        parkingHeightM: pH,
        vehicleLengthM: vL,
        vehicleWidthM: vW,
        vehicleHeightM: vH,
      );
      expect(result, FitResult.tightFit);
      expect(FitCheckService.wire(result), 'TIGHT_FIT');
    });

    test('clearance narrower than +0.30 m => TIGHT_FIT', () {
      final result = FitCheckService.check(
        parkingLengthM: pL,
        parkingWidthM: 2.09, // 0.29 clearance
        parkingHeightM: pH,
        vehicleLengthM: vL,
        vehicleWidthM: vW,
        vehicleHeightM: vH,
      );
      expect(result, FitResult.tightFit);
    });

    test('vehicle taller than parking => DOES_NOT_FIT', () {
      final result = FitCheckService.check(
        parkingLengthM: pL,
        parkingWidthM: pW,
        parkingHeightM: 1.40,
        vehicleLengthM: vL,
        vehicleWidthM: vW,
        vehicleHeightM: vH,
      );
      expect(result, FitResult.doesNotFit);
      expect(FitCheckService.wire(result), 'DOES_NOT_FIT');
    });

    test('vehicle longer than parking => DOES_NOT_FIT', () {
      final result = FitCheckService.check(
        parkingLengthM: 3.90,
        parkingWidthM: pW,
        parkingHeightM: pH,
        vehicleLengthM: vL,
        vehicleWidthM: vW,
        vehicleHeightM: vH,
      );
      expect(result, FitResult.doesNotFit);
    });

    test('exactly on the margin boundary counts as FIT (>= margins)', () {
      // Length lands exactly on +0.50 in binary FP (4.50 - 4.00 == 0.5);
      // width/height have generous clearance so only length is on the edge.
      final result = FitCheckService.check(
        parkingLengthM: 4.50, // exactly +0.50
        parkingWidthM: 2.80, // +1.00
        parkingHeightM: 2.50, // +1.00
        vehicleLengthM: vL,
        vehicleWidthM: vW,
        vehicleHeightM: vH,
      );
      expect(result, FitResult.fit);
    });
  });

  group('FitCheckService.vehicleAllowed', () {
    test('BOTH parking accepts bikes and cars', () {
      expect(FitCheckService.vehicleAllowed('BOTH', 'BIKE'), isTrue);
      expect(FitCheckService.vehicleAllowed('BOTH', 'CAR'), isTrue);
    });

    test('BIKE parking only accepts bikes', () {
      expect(FitCheckService.vehicleAllowed('BIKE', 'BIKE'), isTrue);
      expect(FitCheckService.vehicleAllowed('BIKE', 'CAR'), isFalse);
    });

    test('CAR parking only accepts cars', () {
      expect(FitCheckService.vehicleAllowed('CAR', 'CAR'), isTrue);
      expect(FitCheckService.vehicleAllowed('CAR', 'BIKE'), isFalse);
    });
  });
}
