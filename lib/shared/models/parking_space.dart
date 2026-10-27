/// Individual physical parking slot (a `parking_spaces` row).
///
/// A parking listing is made of slots (C1, C2, B1, B2 …). A booking occupies
/// exactly ONE slot for its date range, which is what keeps the rest of the
/// property bookable.
library;

import '../../core/utils/helpers.dart';

/// Vehicle types a slot can be sized for.
class ParkingSpaceVehicleType {
  ParkingSpaceVehicleType._();
  static const String bike = 'BIKE';
  static const String car = 'CAR';
  static const List<String> all = [bike, car];

  /// "Car"/"Bike" for UI copy.
  static String label(String type) => type == car ? 'Car' : 'Bike';
}

class ParkingSpace {
  final String id;
  final String parkingId;

  /// Short owner-facing identifier, e.g. `C1`. Unique per listing.
  final String spaceCode;
  final String? spaceName;

  /// BIKE or CAR — a car never consumes a bike slot.
  final String vehicleType;
  final double? lengthM;
  final double? widthM;
  final double? heightM;
  final bool isActive;

  /// Only present when the server computed it for a specific date window.
  final bool? available;

  /// Only present when the server computed it for a specific date window.
  /// Factual, date-only: an occupying booking overlaps the window. Lets the UI
  /// say "Booked" instead of guessing why a slot is greyed out.
  final bool? booked;

  const ParkingSpace({
    required this.id,
    required this.parkingId,
    required this.spaceCode,
    this.spaceName,
    required this.vehicleType,
    this.lengthM,
    this.widthM,
    this.heightM,
    this.isActive = true,
    this.available,
    this.booked,
  });

  bool get isCar => vehicleType == ParkingSpaceVehicleType.car;
  bool get isBike => vehicleType == ParkingSpaceVehicleType.bike;

  /// `8.20 × 16.40 ft` style summary (shown in feet; stored in meters), or an
  /// em dash when the slot has no size.
  String get dimensionLabel {
    final l = lengthM;
    final w = widthM;
    if (l == null || w == null) return '—';
    return '${Helpers.feetLabel(w, decimals: 2)} × '
        '${Helpers.feetLabel(l, decimals: 2)}';
  }

  /// The label shown on cards: the owner's name when given, else the code.
  String get displayLabel {
    final n = spaceName?.trim() ?? '';
    return n.isEmpty ? spaceCode : n;
  }

  factory ParkingSpace.fromJson(Map<String, dynamic> json) => ParkingSpace(
    id: json['id']?.toString() ?? '',
    parkingId: json['parkingId']?.toString() ?? '',
    spaceCode: json['spaceCode']?.toString() ?? '',
    spaceName: json['spaceName']?.toString(),
    vehicleType: json['vehicleType']?.toString() ?? ParkingSpaceVehicleType.car,
    lengthM: _d(json['lengthM']),
    widthM: _d(json['widthM']),
    heightM: _d(json['heightM']),
    isActive: json['isActive'] != false,
    available: json['available'] == null ? null : json['available'] == true,
    booked: json['booked'] == null ? null : json['booked'] == true,
  );

  /// Owner-side draft row: everything the wizard edits before it is saved.
  factory ParkingSpace.draft({
    required String spaceCode,
    String? spaceName,
    required String vehicleType,
    double? lengthM,
    double? widthM,
    double? heightM,
  }) => ParkingSpace(
    id: '',
    parkingId: '',
    spaceCode: spaceCode,
    spaceName: spaceName,
    vehicleType: vehicleType,
    lengthM: lengthM,
    widthM: widthM,
    heightM: heightM,
  );

  /// API payload for the wizard (`spaces` array on create/update).
  Map<String, dynamic> toPayload() => {
    'spaceCode': spaceCode,
    'spaceName': (spaceName?.trim().isEmpty ?? true) ? null : spaceName!.trim(),
    'vehicleType': vehicleType,
    'lengthM': lengthM,
    'widthM': widthM,
    'heightM': heightM,
  };

  ParkingSpace copyWith({
    String? spaceCode,
    String? spaceName,
    String? vehicleType,
    double? lengthM,
    double? widthM,
    double? heightM,
  }) => ParkingSpace(
    id: id,
    parkingId: parkingId,
    spaceCode: spaceCode ?? this.spaceCode,
    spaceName: spaceName ?? this.spaceName,
    vehicleType: vehicleType ?? this.vehicleType,
    lengthM: lengthM ?? this.lengthM,
    widthM: widthM ?? this.widthM,
    heightM: heightM ?? this.heightM,
    isActive: isActive,
    available: available,
    booked: booked,
  );

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

/// A `carSpaces` / `bikeSpaces` `{total, available}` pair.
class ParkingSpacePool {
  final int total;
  final int available;
  const ParkingSpacePool({this.total = 0, this.available = 0});

  bool get isEmpty => total == 0;
  bool get isFull => total > 0 && available == 0;
  bool get hasFree => available > 0;

  factory ParkingSpacePool.fromJson(Map<String, dynamic>? json) {
    int n(dynamic v) =>
        v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);
    return ParkingSpacePool(
      total: n(json?['total']),
      available: n(json?['available']),
    );
  }
}

/// Owner dashboard utilisation for one parking (occupied / available per type).
class ParkingUtilisation {
  final ParkingSpacePool carSpaces;
  final ParkingSpacePool bikeSpaces;
  const ParkingUtilisation({
    this.carSpaces = const ParkingSpacePool(),
    this.bikeSpaces = const ParkingSpacePool(),
  });

  factory ParkingUtilisation.fromJson(Map<String, dynamic> json) =>
      ParkingUtilisation(
        carSpaces: ParkingSpacePool.fromJson(
          json['carSpaces'] as Map<String, dynamic>?,
        ),
        bikeSpaces: ParkingSpacePool.fromJson(
          json['bikeSpaces'] as Map<String, dynamic>?,
        ),
      );
}

/// Date-window + vehicle-aware availability of one parking.
///
/// Everything the user screens show about "is it free" comes from here — no
/// hardcoded counts anywhere.
class ParkingAvailability {
  final String parkingId;
  final DateTime? startDate;
  final DateTime? endDate;

  /// BIKE / CAR, or null when no vehicle was supplied.
  final String? vehicleType;

  /// Slots of [vehicleType] (2 for a car user on a 2-car listing, …).
  final int totalSpaces;

  /// Free slots of [vehicleType] that the vehicle actually fits into.
  final int availableSpaces;
  final bool isAvailable;

  /// At least one slot of this type could physically hold the vehicle,
  /// regardless of bookings. Distinguishes "full" from "too small".
  final bool fitsAnySpace;

  /// A pre-migration booking (no slot) holds the whole property.
  final bool legacyParkingBlocked;
  final ParkingSpacePool carSpaces;
  final ParkingSpacePool bikeSpaces;

  const ParkingAvailability({
    required this.parkingId,
    this.startDate,
    this.endDate,
    this.vehicleType,
    this.totalSpaces = 0,
    this.availableSpaces = 0,
    this.isAvailable = false,
    this.fitsAnySpace = false,
    this.legacyParkingBlocked = false,
    this.carSpaces = const ParkingSpacePool(),
    this.bikeSpaces = const ParkingSpacePool(),
  });

  /// "Car" / "Bike" for the selected vehicle type.
  String get vehicleLabel =>
      vehicleType == ParkingSpaceVehicleType.bike ? 'Bike' : 'Car';

  /// Every suitable slot is taken. Requires a real verdict (a vehicle was
  /// supplied) so an unevaluated block never reads as "full".
  bool get isFullForVehicle =>
      hasVerdict && totalSpaces > 0 && availableSpaces == 0;

  /// True when the server actually evaluated this for a vehicle, so the counts
  /// mean something. A block built without a vehicle has no verdict.
  bool get hasVerdict => vehicleType != null;

  /// One-line status used on the detail screen, the map preview card and the
  /// booking form. Never invents a count: when the server had no vehicle to
  /// evaluate it falls back to the per-type pools.
  String get statusLine {
    if (!hasVerdict) {
      if (carSpaces.total == 0 && bikeSpaces.total == 0) {
        return 'Parking space details unavailable.';
      }
      final parts = <String>[
        if (carSpaces.total > 0)
          '${carSpaces.available}/${carSpaces.total} car',
        if (bikeSpaces.total > 0)
          '${bikeSpaces.available}/${bikeSpaces.total} bike',
      ];
      return parts.isEmpty
          ? 'Parking space details unavailable.'
          : 'Spaces free: ${parts.join(' · ')}';
    }
    if (totalSpaces == 0) {
      return legacyParkingBlocked
          ? 'No $vehicleLabel spaces available for these dates.'
          : 'No $vehicleLabel parking spaces in this parking.';
    }
    if (availableSpaces == 0) {
      return fitsAnySpace
          ? '$vehicleLabel Parking Full'
          : 'Your vehicle may not fit this parking space.';
    }
    return availableSpaces == 1
        ? '1 $vehicleLabel space available'
        : '$availableSpaces $vehicleLabel spaces available';
  }

  factory ParkingAvailability.fromJson(Map<String, dynamic> json) =>
      ParkingAvailability(
        parkingId: json['parkingId']?.toString() ?? '',
        startDate: DateTime.tryParse(json['startDate']?.toString() ?? ''),
        endDate: DateTime.tryParse(json['endDate']?.toString() ?? ''),
        vehicleType: json['vehicleType']?.toString(),
        totalSpaces: _i(json['totalSpaces']),
        availableSpaces: _i(json['availableSpaces']),
        isAvailable: json['isAvailable'] == true,
        fitsAnySpace: json['fitsAnySpace'] == true,
        legacyParkingBlocked: json['legacyParkingBlocked'] == true,
        carSpaces: ParkingSpacePool.fromJson(
          json['carSpaces'] as Map<String, dynamic>?,
        ),
        bikeSpaces: ParkingSpacePool.fromJson(
          json['bikeSpaces'] as Map<String, dynamic>?,
        ),
      );

  static int _i(dynamic v) =>
      v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);
}
