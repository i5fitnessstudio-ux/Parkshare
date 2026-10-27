/// Vehicle domain constants + row -> JSON mapping (backend).
class VehicleType {
  VehicleType._();
  static const String bike = 'BIKE';
  static const String car = 'CAR';
  static const Set<String> all = {bike, car};
}

Map<String, dynamic> vehicleRowToJson(Map<String, dynamic> row) {
  return {
    'id': row['id']?.toString() ?? '',
    'userId': row['user_id']?.toString() ?? '',
    'vehicleType': row['vehicle_type']?.toString() ?? VehicleType.car,
    'brand': row['brand']?.toString() ?? '',
    'model': row['model']?.toString() ?? '',
    'registrationNumber': row['registration_number']?.toString() ?? '',
    'photoUrl': row['photo_url']?.toString(),
    'lengthM': double.tryParse(row['length_m']?.toString() ?? ''),
    'widthM': double.tryParse(row['width_m']?.toString() ?? ''),
    'heightM': double.tryParse(row['height_m']?.toString() ?? ''),
    'isPrimary': row['is_primary'] == true,
    'createdAt': (row['created_at'] as DateTime?)?.toIso8601String() ?? '',
    'updatedAt': (row['updated_at'] as DateTime?)?.toIso8601String() ?? '',
  };
}
