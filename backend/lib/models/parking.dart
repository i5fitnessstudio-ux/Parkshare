/// Parking domain constants + row -> JSON mapping (backend).
class ParkingType {
  ParkingType._();
  static const String nonCovered = 'NON_COVERED';
  static const String covered = 'COVERED';
  static const Set<String> all = {nonCovered, covered};
}

class ParkingVehicleType {
  ParkingVehicleType._();
  static const String bike = 'BIKE';
  static const String car = 'CAR';
  static const String both = 'BOTH';
  static const Set<String> all = {bike, car, both};
}

/// Standard amenity labels stored verbatim in parking_amenities.
class ParkingAmenity {
  ParkingAmenity._();
  static const String cctv = 'CCTV';
  static const String covered = 'Covered Parking';
  static const String security = 'Security';
  static const String evCharging = 'EV Charging';
  static const String lighting = 'Lighting';
  static const String access247 = '24/7 Access';
  static const String gateAccess = 'Gate Access';
  static const String wheelchair = 'Wheelchair Accessible';
  static const String waterWash = 'Water Wash';
  static const String twoWheeler = 'Two Wheeler Allowed';
  static const String carAllowed = 'Car Allowed';
  static const List<String> all = [
    cctv,
    covered,
    security,
    evCharging,
    lighting,
    access247,
    gateAccess,
    wheelchair,
    waterWash,
    twoWheeler,
    carAllowed,
  ];
}

/// Capacity mode chosen by the owner on the "Estimated Capacity" step.
/// Maps 1:1 onto the existing `parking_listings.vehicle_type` enum.
class ParkingCapacityMode {
  ParkingCapacityMode._();
  static const String cars = 'CAR';
  static const String bikes = 'BIKE';
  static const String both = 'BOTH';
  static const Set<String> all = {cars, bikes, both};
}

/// Converts a parking_listings row (from `toColumnMap()`) plus child data
/// into the API JSON shape. Keys are camelCase, dimensions are raw meters.
///
/// [spaces] are the individual physical slots; [availability] is only
/// included when the caller actually computed a vehicle-type/date window.
Map<String, dynamic> parkingRowToJson(
  Map<String, dynamic> row, {
  String? ownerName,
  List<String> photoUrls = const [],
  List<String> amenities = const [],
  double? distanceKm,
  Map<String, dynamic>? currentBooking,
  String? availableFrom,
  bool? availableOverride,
  List<Map<String, dynamic>> spaces = const [],
  Map<String, dynamic>? availability,
  Map<String, dynamic>? utilisation,
}) {
  double? d(String? v) => v == null ? null : double.tryParse(v.toString());
  int n(Object? v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
  final carTotal = spaces
      .where((s) => s['vehicleType'] == ParkingVehicleType.car)
      .length;
  final bikeTotal = spaces
      .where((s) => s['vehicleType'] == ParkingVehicleType.bike)
      .length;
  return {
    'id': row['id']?.toString() ?? '',
    'ownerId': row['owner_id']?.toString() ?? '',
    'ownerName': ownerName ?? '',
    'parkingName': row['parking_name']?.toString() ?? '',
    'address': row['address']?.toString() ?? '',
    'city': row['city']?.toString(),
    'state': row['state']?.toString(),
    'pincode': row['pincode']?.toString(),
    'landmark': row['landmark']?.toString(),
    'latitude': (row['latitude'] as num?)?.toDouble(),
    'longitude': (row['longitude'] as num?)?.toDouble(),
    'parkingType': row['parking_type']?.toString() ?? ParkingType.nonCovered,
    'lengthM': d(row['length_m']?.toString()),
    'widthM': d(row['width_m']?.toString()),
    'heightM': d(row['height_m']?.toString()),
    'entranceLengthM': d(row['entrance_length_m']?.toString()),
    'entranceWidthM': d(row['entrance_width_m']?.toString()),
    'entranceHeightM': d(row['entrance_height_m']?.toString()),
    'vehicleType': row['vehicle_type']?.toString() ?? ParkingVehicleType.both,
    'monthlyEnabled': row['monthly_enabled'] == true,
    'monthlyRent': d(row['monthly_rent']?.toString()),
    'yearlyEnabled': row['yearly_enabled'] == true,
    'yearlyRent': d(row['yearly_rent']?.toString()),
    // ---- Per-vehicle plans (car/bike x monthly/yearly) ----
    // A row written before migration 006 (per_vehicle_plans = FALSE) reports
    // its legacy pair for BOTH vehicle types, so the client never loses a
    // working plan.
    'carMonthlyEnabled': _planEnabled(
      row,
      'car_monthly_enabled',
      'monthly_enabled',
    ),
    'carMonthlyRent': _planRent(row, 'car_monthly_rent', 'monthly_rent'),
    'carYearlyEnabled': _planEnabled(
      row,
      'car_yearly_enabled',
      'yearly_enabled',
    ),
    'carYearlyRent': _planRent(row, 'car_yearly_rent', 'yearly_rent'),
    'bikeMonthlyEnabled': _planEnabled(
      row,
      'bike_monthly_enabled',
      'monthly_enabled',
    ),
    'bikeMonthlyRent': _planRent(row, 'bike_monthly_rent', 'monthly_rent'),
    'bikeYearlyEnabled': _planEnabled(
      row,
      'bike_yearly_enabled',
      'yearly_enabled',
    ),
    'bikeYearlyRent': _planRent(row, 'bike_yearly_rent', 'yearly_rent'),
    'accessHours': row['access_hours']?.toString() ?? '24/7',
    'description': row['description']?.toString() ?? '',
    'conditions': row['conditions']?.toString() ?? '',
    'available': availableOverride ?? row['available'] == true,
    'autoApproval': row['auto_approval'] == true,
    'photoUrls': photoUrls,
    'thumbnailUrl': photoUrls.isNotEmpty ? photoUrls.first : null,
    'amenities': amenities,
    'distanceKm': distanceKm,
    'currentBooking': currentBooking,
    'availableFrom': availableFrom,
    // ---- Slot-based capacity (parking_spaces) ----
    'maximumCars': n(row['maximum_cars']),
    'maximumBikes': n(row['maximum_bikes']),
    'allowMixedParking': row['allow_mixed_parking'] == true,
    'totalCarSpaces': carTotal,
    'totalBikeSpaces': bikeTotal,
    if (spaces.isNotEmpty) 'spaces': spaces,
    'availability': ?availability,
    'utilisation': ?utilisation,
    'rating': null,
    'createdAt': (row['created_at'] as DateTime?)?.toIso8601String() ?? '',
    'updatedAt': (row['updated_at'] as DateTime?)?.toIso8601String() ?? '',
  };
}

/// A per-vehicle plan flag read with a legacy fallback: rows saved before
/// migration 006 (`per_vehicle_plans = FALSE`) fall back to the shared
/// monthly/yearly columns for BOTH vehicle types.
bool _planEnabled(Map<String, dynamic> row, String key, String legacyKey) =>
    row['per_vehicle_plans'] == true
    ? row[key] == true
    : row[legacyKey] == true;

double? _planRent(Map<String, dynamic> row, String key, String legacyKey) {
  final raw = row['per_vehicle_plans'] == true ? row[key] : row[legacyKey];
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}
