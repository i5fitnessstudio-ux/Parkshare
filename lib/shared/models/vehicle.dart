/// Vehicle domain model (Vehicle User's saved vehicles).
class VehicleType {
  VehicleType._();
  static const String bike = 'BIKE';
  static const String car = 'CAR';
}

class Vehicle {
  final String id;
  final String userId;
  final String vehicleType; // BIKE | CAR
  final String brand;
  final String model;
  final String registrationNumber;
  final String? photoUrl;
  final double? lengthM;
  final double? widthM;
  final double? heightM;
  final bool isPrimary;

  const Vehicle({
    required this.id,
    required this.userId,
    required this.vehicleType,
    required this.brand,
    required this.model,
    required this.registrationNumber,
    this.photoUrl,
    this.lengthM,
    this.widthM,
    this.heightM,
    this.isPrimary = false,
  });

  bool get isBike => vehicleType == VehicleType.bike;

  String get displayName =>
      '${brand.isNotEmpty ? '$brand ' : ''}$model'.trim().isEmpty
      ? 'Unnamed vehicle'
      : '$brand $model'.trim();

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    double? d(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return Vehicle(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      vehicleType: json['vehicleType']?.toString() ?? VehicleType.car,
      brand: json['brand']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      registrationNumber: json['registrationNumber']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString(),
      lengthM: d(json['lengthM']),
      widthM: d(json['widthM']),
      heightM: d(json['heightM']),
      isPrimary: json['isPrimary'] == true,
    );
  }
}
