/// Individual physical parking slot (a `parking_spaces` row).
///
/// A parking listing is made of slots (C1, C2, B1, B2 …). A booking occupies
/// exactly ONE slot for its date range, which is what keeps the rest of the
/// property bookable.
library;

class ParkingSpaceVehicleType {
  ParkingSpaceVehicleType._();
  static const String bike = 'BIKE';
  static const String car = 'CAR';
  static const Set<String> all = {bike, car};
}

/// Converts a `parking_spaces` row into API JSON (camelCase, metres).
///
/// [available] is the booking verdict for the requested window: free AND big
/// enough for the vehicle AND reachable through the gate. [booked] says the
/// narrower, factual thing — an occupying booking overlaps the window — so a
/// client can label a greyed-out slot "Booked" vs "Unavailable" (too small,
/// gate too tight, or deactivated) instead of guessing.
Map<String, dynamic> parkingSpaceRowToJson(
  Map<String, dynamic> row, {
  bool? available,
  bool? booked,
}) {
  double? d(Object? v) => v == null ? null : double.tryParse(v.toString());
  return {
    'id': row['id']?.toString() ?? '',
    'parkingId': row['parking_id']?.toString() ?? '',
    'spaceCode': row['space_code']?.toString() ?? '',
    'spaceName': row['space_name']?.toString() ?? '',
    'vehicleType':
        row['vehicle_type']?.toString() ?? ParkingSpaceVehicleType.car,
    'lengthM': d(row['length_m']),
    'widthM': d(row['width_m']),
    'heightM': d(row['height_m']),
    'isActive': row['is_active'] != false,
    'available': ?available,
    'booked': ?booked,
  };
}
