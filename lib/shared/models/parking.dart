/// Parking domain model (backend JSON keys are camelCase).
library;

import 'parking_space.dart';

class ParkingType {
  ParkingType._();
  static const String nonCovered = 'NON_COVERED';
  static const String covered = 'COVERED';
}

class ParkingListing {
  final String id;
  final String ownerId;
  final String ownerName;
  final String parkingName;
  final String address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? landmark;
  final double? latitude;
  final double? longitude;
  final String parkingType;
  final double? lengthM;
  final double? widthM;
  final double? heightM;
  final double? entranceLengthM;
  final double? entranceWidthM;
  final double? entranceHeightM;
  final String vehicleType; // BIKE | CAR | BOTH
  final bool monthlyEnabled;
  final double? monthlyRent;
  final bool yearlyEnabled;
  final double? yearlyRent;

  // ---- Per-vehicle rental plans (car/bike × monthly/yearly) ---------------
  /// Each plan is configured and priced independently by the owner. Listings
  /// saved before the split report the legacy monthly/yearly pair for BOTH
  /// vehicle types, so the UI never loses a working plan.
  final bool carMonthlyEnabled;
  final double? carMonthlyRent;
  final bool carYearlyEnabled;
  final double? carYearlyRent;
  final bool bikeMonthlyEnabled;
  final double? bikeMonthlyRent;
  final bool bikeYearlyEnabled;
  final double? bikeYearlyRent;
  final String accessHours;
  final String description;
  final String conditions;
  final bool available;
  final bool autoApproval;
  final List<String> photoUrls;
  final String? thumbnailUrl;
  final List<String> amenities;
  final double? distanceKm;
  final Map<String, dynamic>? currentBooking;
  final String? availableFrom;

  // ---- Slot-based capacity -------------------------------------------------
  /// Capacity the owner entered, mirrored from the real slot rows server-side.
  final int maximumCars;
  final int maximumBikes;
  final bool allowMixedParking;

  /// The individual physical slots of this listing (C1, C2, B1 …).
  final List<ParkingSpace> spaces;

  /// Present only when the caller asked for a vehicle / date window.
  final ParkingAvailability? availability;

  /// Owner-side slot utilisation (occupied / available per type). Present on
  /// the owner dashboard reads.
  final ParkingUtilisation? utilisation;

  const ParkingListing({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.parkingName,
    required this.address,
    this.city,
    this.state,
    this.pincode,
    this.landmark,
    this.latitude,
    this.longitude,
    required this.parkingType,
    this.lengthM,
    this.widthM,
    this.heightM,
    this.entranceLengthM,
    this.entranceWidthM,
    this.entranceHeightM,
    required this.vehicleType,
    required this.monthlyEnabled,
    this.monthlyRent,
    required this.yearlyEnabled,
    this.yearlyRent,
    this.carMonthlyEnabled = false,
    this.carMonthlyRent,
    this.carYearlyEnabled = false,
    this.carYearlyRent,
    this.bikeMonthlyEnabled = false,
    this.bikeMonthlyRent,
    this.bikeYearlyEnabled = false,
    this.bikeYearlyRent,
    this.accessHours = '24/7',
    this.description = '',
    this.conditions = '',
    this.available = true,
    this.autoApproval = false,
    this.photoUrls = const [],
    this.thumbnailUrl,
    this.amenities = const [],
    this.distanceKm,
    this.currentBooking,
    this.availableFrom,
    this.maximumCars = 0,
    this.maximumBikes = 0,
    this.allowMixedParking = false,
    this.spaces = const [],
    this.availability,
    this.utilisation,
  });

  bool get isCovered => parkingType == ParkingType.covered;

  bool get acceptsBikes => vehicleType == 'BIKE' || vehicleType == 'BOTH';
  bool get acceptsCars => vehicleType == 'CAR' || vehicleType == 'BOTH';

  // ---- Slot helpers --------------------------------------------------------

  /// Real slot counts, falling back to the capacity columns for a listing that
  /// has not been re-saved since the migration.
  int get totalCarSpaces =>
      spaces.isNotEmpty ? spaces.where((s) => s.isCar).length : maximumCars;
  int get totalBikeSpaces =>
      spaces.isNotEmpty ? spaces.where((s) => s.isBike).length : maximumBikes;
  int get totalSpaces => totalCarSpaces + totalBikeSpaces;

  List<ParkingSpace> get carSpaces =>
      spaces.where((s) => s.isCar).toList(growable: false);
  List<ParkingSpace> get bikeSpaces =>
      spaces.where((s) => s.isBike).toList(growable: false);

  /// The slot the listing promises for [vehicleType] (used to judge whether a
  /// marker is bookable without a full availability round-trip).
  bool hasSlotFor(String type) =>
      type == 'BIKE' ? totalBikeSpaces > 0 : totalCarSpaces > 0;

  /// The rent plans that apply to ONE vehicle type: the dedicated car/bike
  /// values, falling back to the legacy monthly/yearly pair for a listing
  /// saved before the split. A null (or unknown) vehicle type resolves to the
  /// union of both types' plans, so a screen that has not picked a vehicle
  /// yet still offers every available plan.
  RentPlan planFor(String? vehicleType) {
    switch (vehicleType) {
      case 'BIKE':
        return RentPlan(
          monthlyEnabled: bikeMonthlyEnabled,
          monthlyRent: bikeMonthlyRent,
          yearlyEnabled: bikeYearlyEnabled,
          yearlyRent: bikeYearlyRent,
        );
      case 'CAR':
        return RentPlan(
          monthlyEnabled: carMonthlyEnabled,
          monthlyRent: carMonthlyRent,
          yearlyEnabled: carYearlyEnabled,
          yearlyRent: carYearlyRent,
        );
      default:
        return RentPlan(
          monthlyEnabled: carMonthlyEnabled || bikeMonthlyEnabled,
          monthlyRent: carMonthlyRent ?? bikeMonthlyRent,
          yearlyEnabled: carYearlyEnabled || bikeYearlyEnabled,
          yearlyRent: carYearlyRent ?? bikeYearlyRent,
        );
    }
  }

  double? get cheapestRent {
    final rents = <double>[
      if (monthlyEnabled && monthlyRent != null) monthlyRent!,
      if (yearlyEnabled && yearlyRent != null) yearlyRent!,
      if (carMonthlyEnabled && carMonthlyRent != null) carMonthlyRent!,
      if (carYearlyEnabled && carYearlyRent != null) carYearlyRent!,
      if (bikeMonthlyEnabled && bikeMonthlyRent != null) bikeMonthlyRent!,
      if (bikeYearlyEnabled && bikeYearlyRent != null) bikeYearlyRent!,
    ];
    if (rents.isEmpty) return null;
    rents.sort();
    return rents.first;
  }

  factory ParkingListing.fromJson(Map<String, dynamic> json) {
    List<String> strList(dynamic raw) => (raw is List)
        ? raw.map((e) => e.toString()).toList()
        : const <String>[];
    return ParkingListing(
      id: json['id']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      ownerName: json['ownerName']?.toString() ?? '',
      parkingName: json['parkingName']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      city: json['city']?.toString(),
      state: json['state']?.toString(),
      pincode: json['pincode']?.toString(),
      landmark: json['landmark']?.toString(),
      latitude: _d(json['latitude']),
      longitude: _d(json['longitude']),
      parkingType: json['parkingType']?.toString() ?? ParkingType.nonCovered,
      lengthM: _d(json['lengthM']),
      widthM: _d(json['widthM']),
      heightM: _d(json['heightM']),
      entranceLengthM: _d(json['entranceLengthM']),
      entranceWidthM: _d(json['entranceWidthM']),
      entranceHeightM: _d(json['entranceHeightM']),
      vehicleType: json['vehicleType']?.toString() ?? 'BOTH',
      monthlyEnabled: json['monthlyEnabled'] == true,
      monthlyRent: _d(json['monthlyRent']),
      yearlyEnabled: json['yearlyEnabled'] == true,
      yearlyRent: _d(json['yearlyRent']),
      // Per-vehicle plans; pre-split payloads (no car/bike keys) fall back to
      // the legacy monthly/yearly pair for every vehicle type.
      carMonthlyEnabled: json.containsKey('carMonthlyEnabled')
          ? json['carMonthlyEnabled'] == true
          : json['monthlyEnabled'] == true,
      carMonthlyRent: _d(
        json.containsKey('carMonthlyRent')
            ? json['carMonthlyRent']
            : json['monthlyRent'],
      ),
      carYearlyEnabled: json.containsKey('carYearlyEnabled')
          ? json['carYearlyEnabled'] == true
          : json['yearlyEnabled'] == true,
      carYearlyRent: _d(
        json.containsKey('carYearlyRent')
            ? json['carYearlyRent']
            : json['yearlyRent'],
      ),
      bikeMonthlyEnabled: json.containsKey('bikeMonthlyEnabled')
          ? json['bikeMonthlyEnabled'] == true
          : json['monthlyEnabled'] == true,
      bikeMonthlyRent: _d(
        json.containsKey('bikeMonthlyRent')
            ? json['bikeMonthlyRent']
            : json['monthlyRent'],
      ),
      bikeYearlyEnabled: json.containsKey('bikeYearlyEnabled')
          ? json['bikeYearlyEnabled'] == true
          : json['yearlyEnabled'] == true,
      bikeYearlyRent: _d(
        json.containsKey('bikeYearlyRent')
            ? json['bikeYearlyRent']
            : json['yearlyRent'],
      ),
      accessHours: json['accessHours']?.toString() ?? '24/7',
      description: json['description']?.toString() ?? '',
      conditions: json['conditions']?.toString() ?? '',
      available: json['available'] != false,
      autoApproval: json['autoApproval'] == true,
      photoUrls: strList(json['photoUrls']),
      thumbnailUrl:
          json['thumbnailUrl']?.toString() ??
          ((json['photoUrls'] is List && (json['photoUrls'] as List).isNotEmpty)
              ? json['photoUrls'].first.toString()
              : null),
      amenities: strList(json['amenities']),
      distanceKm: _d(json['distanceKm']),
      currentBooking: json['currentBooking'] is Map<String, dynamic>
          ? json['currentBooking'] as Map<String, dynamic>
          : null,
      availableFrom: json['availableFrom']?.toString(),
      maximumCars: _i(json['maximumCars']),
      maximumBikes: _i(json['maximumBikes']),
      allowMixedParking: json['allowMixedParking'] == true,
      spaces: (json['spaces'] is List)
          ? (json['spaces'] as List)
                .whereType<Map<String, dynamic>>()
                .map(ParkingSpace.fromJson)
                .toList()
          : const <ParkingSpace>[],
      availability: json['availability'] is Map<String, dynamic>
          ? ParkingAvailability.fromJson(
              json['availability'] as Map<String, dynamic>,
            )
          : null,
      utilisation: json['utilisation'] is Map<String, dynamic>
          ? ParkingUtilisation.fromJson(
              json['utilisation'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _i(dynamic v) =>
      v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);
}

/// The rental plans that apply to ONE vehicle type (car or bike), resolved
/// from the per-vehicle fields (or the legacy monthly/yearly pair).
class RentPlan {
  final bool monthlyEnabled;
  final double? monthlyRent;
  final bool yearlyEnabled;
  final double? yearlyRent;

  const RentPlan({
    required this.monthlyEnabled,
    this.monthlyRent,
    required this.yearlyEnabled,
    this.yearlyRent,
  });

  bool get anyEnabled => monthlyEnabled || yearlyEnabled;
}

/// Vehicles accepted by a parking ("BIKE", "CAR", "BOTH").
class AcceptedVehicle {
  AcceptedVehicle._();
  static const String bike = 'BIKE';
  static const String car = 'CAR';
  static const String both = 'BOTH';
}
