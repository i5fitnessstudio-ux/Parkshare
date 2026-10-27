/// Dimensional fit check — pure Dart, mirrors the backend validation exactly.
///
/// A parking space fits a vehicle when all three dimensions are large
/// enough; a comfortable fit additionally requires clearance margins:
///   length +0.50 m, width +0.30 m, height +0.15 m.
enum FitResult { fit, tightFit, doesNotFit }

class FitCheckService {
  FitCheckService._();

  static const double lengthClearanceM = 0.50;
  static const double widthClearanceM = 0.30;
  static const double heightClearanceM = 0.15;

  /// Computes the fit result using metres only.
  static FitResult check({
    required double parkingLengthM,
    required double parkingWidthM,
    required double parkingHeightM,
    required double vehicleLengthM,
    required double vehicleWidthM,
    required double vehicleHeightM,
  }) {
    if (parkingLengthM < vehicleLengthM ||
        parkingWidthM < vehicleWidthM ||
        parkingHeightM < vehicleHeightM) {
      return FitResult.doesNotFit;
    }
    final lengthClear = parkingLengthM - vehicleLengthM;
    final widthClear = parkingWidthM - vehicleWidthM;
    final heightClear = parkingHeightM - vehicleHeightM;
    if (lengthClear < lengthClearanceM ||
        widthClear < widthClearanceM ||
        heightClear < heightClearanceM) {
      return FitResult.tightFit;
    }
    return FitResult.fit;
  }

  /// Whether the parking accepts the vehicle type. Parking types:
  /// BOTH (all), BIKE (bikes), CAR (cars).
  static bool vehicleAllowed(String parkingVehicleType, String vehicleType) {
    if (parkingVehicleType == 'BOTH') return true;
    return parkingVehicleType == vehicleType;
  }

  /// API wire value for the result.
  static String wire(FitResult result) => switch (result) {
    FitResult.fit => 'FIT',
    FitResult.tightFit => 'TIGHT_FIT',
    FitResult.doesNotFit => 'DOES_NOT_FIT',
  };
}

/// Display helpers for [FitResult].
extension FitResultLabel on FitResult {
  String get label => switch (this) {
    FitResult.fit => 'Perfect Fit',
    FitResult.tightFit => 'Tight Fit',
    FitResult.doesNotFit => 'Does Not Fit',
  };
}
