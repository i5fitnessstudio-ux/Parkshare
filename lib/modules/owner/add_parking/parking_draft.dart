import '../../../core/services/photo_picker_service.dart';
import '../../../shared/models/parking_space.dart';

/// Amenity keys that map 1:1 to `parking_amenities` rows. Absence means
/// *not selected* (no fake rows, no default amenities).
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
  ];
}

/// In-progress owner parking listing. All step data accumulates here; the
/// review step shows the REAL draft and publishing posts this payload.
class ParkingDraft {
  // Step 1: Photos
  List<PickedPhoto> photos = [];

  // Step 2: Details
  String parkingName = '';
  String address = '';
  String city = '';
  String state = '';
  String pincode = '';
  String landmark = '';

  // Step 3: Location
  double? latitude;
  double? longitude;

  // Step 4: Dimensions. The FORM collects feet; the draft (and the API) keep
  // METERS, converted at the input boundary by Helpers.feetToMeters.
  double? lengthM;
  double? widthM;
  double? heightM;
  double? entranceLengthM;
  double? entranceWidthM;
  double? entranceHeightM;

  // Step 5: Estimated capacity
  // The owner states how many cars and bikes fit; the steppers create that many
  // real rows on the Parking Spaces step. These two numbers are re-derived from
  // those rows on every change ([syncCapacityCounters]) and re-derived again
  // server-side on save, so the wizard, the list and the database can never
  // disagree. They start at 0: the owner makes a deliberate choice, and a fresh
  // draft never claims phantom capacity.
  int maximumCars = 0;
  int maximumBikes = 0;
  bool allowMixedParking = false;

  // Step 6: Parking spaces (the individual slots: C1, C2, B1 …)
  final List<ParkingSpace> spaces = [];

  // Step 7: Amenities
  final Set<String> amenities = {};

  // Step 8: Rental plans — one independent plan per vehicle type and period.
  // Each can be switched on/off and priced on its own, so a listing may charge
  // cars and bikes differently, or offer only monthly / only yearly.
  bool carMonthlyEnabled = false;
  double? carMonthlyRent;
  bool carYearlyEnabled = false;
  double? carYearlyRent;
  bool bikeMonthlyEnabled = false;
  double? bikeMonthlyRent;
  bool bikeYearlyEnabled = false;
  double? bikeYearlyRent;

  // Step 9: About
  String parkingType = 'NON_COVERED'; // NON_COVERED | COVERED
  String accessHours = '24/7';
  String description = '';
  String conditions = '';
  bool autoApproval = true;

  bool get hasInternationalMinimum => parkingName.trim().isNotEmpty;

  // -------------------------------------------------------------------------
  // Slot-based capacity helpers
  // -------------------------------------------------------------------------

  /// Real slot counts currently in the draft (never a cached number).
  int get carSpaceCount =>
      spaces.where((s) => s.vehicleType == ParkingSpaceVehicleType.car).length;
  int get bikeSpaceCount =>
      spaces.where((s) => s.vehicleType == ParkingSpaceVehicleType.bike).length;

  List<ParkingSpace> get carSpaces => spaces
      .where((s) => s.vehicleType == ParkingSpaceVehicleType.car)
      .toList(growable: false);
  List<ParkingSpace> get bikeSpaces => spaces
      .where((s) => s.vehicleType == ParkingSpaceVehicleType.bike)
      .toList(growable: false);

  /// The listing's accepted-vehicle mode, DERIVED from the real slots. The
  /// backend re-derives it too, so a car can never end up on a bike-only
  /// listing.
  String get vehicleType {
    if (carSpaceCount > 0 && bikeSpaceCount > 0) return 'BOTH';
    if (bikeSpaceCount > 0) return 'BIKE';
    if (carSpaceCount > 0) return 'CAR';
    return 'BOTH';
  }

  /// A vehicle type is offered when at least one slot of it exists.
  bool offersType(String type) =>
      type == 'BIKE' ? bikeSpaceCount > 0 : carSpaceCount > 0;

  /// Next free code for [type] ("C3" after C1, C2 …), so codes stay readable
  /// and collision-free without the owner typing them.
  String nextSpaceCode(String type) {
    final prefix = type == ParkingSpaceVehicleType.bike ? 'B' : 'C';
    final used = spaces
        .where((s) => s.vehicleType == type)
        .map((s) => s.spaceCode.toUpperCase())
        .toSet();
    var n = 1;
    while (used.contains('$prefix$n')) {
      n++;
    }
    return '$prefix$n';
  }

  /// Grows/shrinks the slot list of [type] to [count], keeping the rows the
  /// owner already customised (code, name, size) and only adding/removing the
  /// difference.
  ///
  /// A NEW slot is always created with an EMPTY length / width / height. The
  /// owner's overall plot dimensions (and the gate dimensions) are a different
  /// concept from one physical bay, so they are never copied in as a default —
  /// the owner measures and types each slot.
  void setCapacity(String type, int count) {
    final target = count < 0 ? 0 : count;
    final pool = spaces.where((s) => s.vehicleType == type).toList();
    if (pool.length != target) {
      if (pool.length < target) {
        for (var i = pool.length; i < target; i++) {
          spaces.add(
            ParkingSpace.draft(
              spaceCode: nextSpaceCode(type),
              spaceName: null,
              vehicleType: type,
            ),
          );
        }
      } else {
        final drop = pool.sublist(target).map((s) => s.spaceCode).toSet();
        spaces.removeWhere((s) => drop.contains(s.spaceCode));
      }
      _reindex(type);
    }
    syncCapacityCounters();
  }

  /// Removes [space] and closes the numbering gap it leaves behind.
  ///
  /// This is the ONLY sanctioned way to drop a slot. Calling it is what keeps
  /// C1, C2, C4 from ever being saved: after the row is gone, the remaining
  /// slots of that type are re-numbered in list order and the stepper counters
  /// are re-derived, so the wizard, the payload and the saved listing agree.
  void removeSpace(ParkingSpace space) {
    final type = space.vehicleType;
    final i = spaces.indexOf(space);
    if (i >= 0) {
      spaces.removeAt(i);
    } else {
      // The captured row can be a stale instance after a re-index; fall back to
      // the (type-scoped, unique) code.
      spaces.removeWhere(
        (s) => s.vehicleType == type && s.spaceCode == space.spaceCode,
      );
    }
    _reindex(type);
    syncCapacityCounters();
  }

  /// Re-derives the stepper counters from the actual slot rows. Run after every
  /// mutation of [spaces] so the wizard numbers, the summary and the payload
  /// can never disagree with the real list.
  void syncCapacityCounters() {
    maximumCars = carSpaceCount;
    maximumBikes = bikeSpaceCount;
  }

  /// Re-numbers codes of [type] to C1..Cn / B1..Bn in list order, so deleting
  /// the middle row never leaves a gap.
  void _reindex(String type) {
    final prefix = type == ParkingSpaceVehicleType.bike ? 'B' : 'C';
    var n = 0;
    for (var i = 0; i < spaces.length; i++) {
      if (spaces[i].vehicleType != type) continue;
      n++;
      spaces[i] = spaces[i].copyWith(spaceCode: '$prefix$n');
    }
  }

  /// "Car Space 2" for a slot, e.g. a blank C2 in a 3-car listing. Used by the
  /// validation copy so the owner is told exactly which row to fill in.
  String labelForSpace(ParkingSpace space) {
    final sameType = spaces
        .where((s) => s.vehicleType == space.vehicleType)
        .toList(growable: false);
    final index = sameType.indexWhere(
      (s) => s.id == space.id && s.spaceCode == space.spaceCode,
    );
    final n = index >= 0 ? index + 1 : sameType.length;
    return '${ParkingSpaceVehicleType.label(space.vehicleType)} Space $n';
  }

  /// Space-level validation. A dimension of 0 is rejected server-side too; this
  /// catches it before the owner leaves the step.
  ///
  /// Every active slot must carry its OWN length, width and height (all > 0).
  /// Nothing is ever back-filled from the plot or the gate, so a missing value
  /// is reported instead of being silently invented.
  String? get spacesError {
    if (spaces.isEmpty) {
      return 'Add at least one parking space (car or bike).';
    }
    for (final s in spaces) {
      if (s.spaceCode.trim().isEmpty) {
        return 'Every parking space needs a code.';
      }
      if ((s.lengthM ?? 0) <= 0 ||
          (s.widthM ?? 0) <= 0 ||
          (s.heightM ?? 0) <= 0) {
        return 'Enter the dimensions for ${labelForSpace(s)}.';
      }
    }
    final codes = spaces.map((s) => s.spaceCode.toUpperCase()).toList();
    if (codes.toSet().length != codes.length) {
      return 'Parking space codes must be unique.';
    }
    return null;
  }

  /// Full address used for Step-2 → map geocoding. Priority is
  /// "Address + City + State + Pincode". The landmark is appended only when
  /// it adds street-level context that the rest cannot (no address, or
  /// neither city nor state). The region ("…, India") is added by the
  /// geocoding service's normaliser.
  String get addressQuery {
    final parts = <String>[
      if (address.trim().isNotEmpty) address.trim(),
      if (city.trim().isNotEmpty) city.trim(),
      if (state.trim().isNotEmpty) state.trim(),
      if (pincode.trim().isNotEmpty) pincode.trim(),
    ];
    if (landmark.trim().isNotEmpty &&
        (address.trim().isEmpty ||
            (city.trim().isEmpty && state.trim().isEmpty))) {
      final insertAt = address.trim().isEmpty ? 0 : 1;
      parts.insert(insertAt, landmark.trim());
    }
    return parts.join(', ');
  }

  /// At least one of the four plans must be offered, and every ENABLED plan
  /// must carry a real amount. Disabled plans are simply not sold — the
  /// server rejects a booking for a plan that is switched off.
  bool get anyRentalPlanEnabled =>
      carMonthlyEnabled ||
      carYearlyEnabled ||
      bikeMonthlyEnabled ||
      bikeYearlyEnabled;

  static String? _planError(String label, bool enabled, double? rent) {
    if (!enabled) return null;
    if (rent == null || rent <= 0) return '$label rent must be greater than 0.';
    return null;
  }

  String? get carMonthlyRentError =>
      _planError('Car monthly', carMonthlyEnabled, carMonthlyRent);
  String? get carYearlyRentError =>
      _planError('Car yearly', carYearlyEnabled, carYearlyRent);
  String? get bikeMonthlyRentError =>
      _planError('Bike monthly', bikeMonthlyEnabled, bikeMonthlyRent);
  String? get bikeYearlyRentError =>
      _planError('Bike yearly', bikeYearlyEnabled, bikeYearlyRent);

  /// First broken plan, in a stable reading order (Car monthly → Bike yearly).
  String? get rentalPlansError =>
      carMonthlyRentError ??
      carYearlyRentError ??
      bikeMonthlyRentError ??
      bikeYearlyRentError;

  /// Server-side rules the wizard must satisfy before publish.
  String? validateForPublish() {
    if (photos.isEmpty) return 'Add at least one photo.';
    if (parkingName.trim().isEmpty) return 'Enter a parking name.';
    if (address.trim().isEmpty) return 'Enter the address.';
    if (latitude == null || longitude == null) {
      return 'Pick the parking location on the map.';
    }
    if (lengthM == null || widthM == null || heightM == null) {
      return 'Enter parking length, width and height.';
    }
    if ((entranceWidthM ?? 0) <= 0) {
      return 'Enter the entrance (gate) width — it decides what can get in.';
    }
    if ((entranceHeightM ?? 0) <= 0) {
      return 'Enter the entrance (gate) height — it decides what can get in.';
    }
    // Entrance length is optional (older listings do not store it), but once the
    // owner types one it must be a real, positive measurement.
    if (entranceLengthM != null && entranceLengthM! <= 0) {
      return 'Entrance (gate) length must be greater than 0.';
    }
    // maximumCars / maximumBikes are DERIVED from the real slot rows, so a
    // "no capacity" state is exactly "no slots". [spacesError] is the single
    // authority for that rule and already says it in slot language.
    final sErr = spacesError;
    if (sErr != null) return sErr;
    if (!anyRentalPlanEnabled) {
      return 'Enable at least one rental plan (car and/or bike).';
    }
    final rErr = rentalPlansError;
    if (rErr != null) return rErr;
    return null;
  }

  /// API payload (camelCase keys) — amount is computed server-side.
  Map<String, dynamic> toPayload(List<String> photoUrls) => {
    'parkingName': parkingName.trim(),
    'address': address.trim(),
    'city': city.trim().isEmpty ? null : city.trim(),
    'state': state.trim().isEmpty ? null : state.trim(),
    'pincode': pincode.trim().isEmpty ? null : pincode.trim(),
    'landmark': landmark.trim().isEmpty ? null : landmark.trim(),
    'latitude': latitude,
    'longitude': longitude,
    'parkingType': parkingType,
    'lengthM': lengthM,
    'widthM': widthM,
    'heightM': heightM,
    'entranceLengthM': entranceLengthM,
    'entranceWidthM': entranceWidthM,
    'entranceHeightM': entranceHeightM,
    // Derived from the real slot rows, never entered by hand.
    'vehicleType': vehicleType,
    'maximumCars': carSpaceCount,
    'maximumBikes': bikeSpaceCount,
    'allowMixedParking': allowMixedParking,
    'spaces': spaces.map((s) => s.toPayload()).toList(),
    // Step 8: the four independent plans (car/bike × monthly/yearly). The
    // legacy monthly/yearly pair is still sent as a DERIVED fallback (car
    // first) so older readers and external consumers keep working.
    'carMonthlyEnabled': carMonthlyEnabled,
    'carMonthlyRent': carMonthlyEnabled ? carMonthlyRent : null,
    'carYearlyEnabled': carYearlyEnabled,
    'carYearlyRent': carYearlyEnabled ? carYearlyRent : null,
    'bikeMonthlyEnabled': bikeMonthlyEnabled,
    'bikeMonthlyRent': bikeMonthlyEnabled ? bikeMonthlyRent : null,
    'bikeYearlyEnabled': bikeYearlyEnabled,
    'bikeYearlyRent': bikeYearlyEnabled ? bikeYearlyRent : null,
    'monthlyEnabled': carMonthlyEnabled || bikeMonthlyEnabled,
    'monthlyRent':
        (carMonthlyEnabled ? carMonthlyRent : null) ??
        (bikeMonthlyEnabled ? bikeMonthlyRent : null),
    'yearlyEnabled': carYearlyEnabled || bikeYearlyEnabled,
    'yearlyRent':
        (carYearlyEnabled ? carYearlyRent : null) ??
        (bikeYearlyEnabled ? bikeYearlyRent : null),
    'accessHours': accessHours.trim().isEmpty ? '24/7' : accessHours.trim(),
    'description': description.trim(),
    'conditions': conditions.trim(),
    'autoApproval': autoApproval,
    'amenities': amenities.toList(),
    'photoUrls': photoUrls,
  };
}
