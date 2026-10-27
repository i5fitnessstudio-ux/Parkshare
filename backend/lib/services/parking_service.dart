import 'dart:math';

import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/booking.dart';
import 'package:parkshare_backend/models/parking.dart';
import 'package:parkshare_backend/models/parking_space.dart';
import 'package:parkshare_backend/services/parking_space_service.dart';
import 'package:postgres/postgres.dart';

/// Domain service for parking listings: create, read, update, delete,
/// owner listing, nearby search (Haversine) and dimensional fit checks.
///
/// All readings/writes go through PostgreSQL. No hard-coded listings.
class ParkingService {
  /// Slot-level capacity (individual parking spaces + date-aware availability).
  final ParkingSpaceService _spaces = ParkingSpaceService();

  // ---------------------------------------------------------------------
  // Fit check (shared by booking validation and returnable to clients)
  // ---------------------------------------------------------------------
  static const double _lengthClearance = 0.50;
  static const double _widthClearance = 0.30;
  static const double _heightClearance = 0.15;

  /// FIT | TIGHT_FIT | DOES_NOT_FIT — metres-only comparison.
  static String fitCheck({
    required double pLength,
    required double pWidth,
    required double pHeight,
    required double vLength,
    required double vWidth,
    required double vHeight,
  }) {
    if (pLength < vLength || pWidth < vWidth || pHeight < vHeight) {
      return 'DOES_NOT_FIT';
    }
    final lenClear = pLength - vLength;
    final widClear = pWidth - vWidth;
    final heiClear = pHeight - vHeight;
    if (lenClear < _lengthClearance ||
        widClear < _widthClearance ||
        heiClear < _heightClearance) {
      return 'TIGHT_FIT';
    }
    return 'FIT';
  }

  static bool vehicleAllowed(String parkingVt, String vehicleVt) {
    if (parkingVt == ParkingVehicleType.both) return true;
    return parkingVt == vehicleVt;
  }

  // ---------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------
  Future<Map<String, dynamic>> create({
    required String ownerId,
    required Map<String, dynamic> body,
  }) async {
    _validatePayload(body);
    final spaces = _spacesFrom(body);
    final plans = _plans(body);

    final parkingId = await Db.pool.withConnection((conn) async {
      final res = await conn.execute(
        Sql.named('''
        INSERT INTO parking_listings (
          owner_id, parking_name, address, city, state, pincode, landmark,
          latitude, longitude, parking_type,
          length_m, width_m, height_m,
          entrance_length_m, entrance_width_m, entrance_height_m,
          vehicle_type, maximum_cars, maximum_bikes, allow_mixed_parking,
          monthly_enabled, monthly_rent, yearly_enabled, yearly_rent,
          car_monthly_enabled, car_monthly_rent,
          car_yearly_enabled, car_yearly_rent,
          bike_monthly_enabled, bike_monthly_rent,
          bike_yearly_enabled, bike_yearly_rent,
          per_vehicle_plans,
          access_hours, description, conditions, available, auto_approval
        ) VALUES (
          @ownerId, @parkingName, @address, @city, @state, @pincode, @landmark,
          @latitude, @longitude, @parkingType,
          @lengthM, @widthM, @heightM,
          @entranceLengthM, @entranceWidthM, @entranceHeightM,
          @vehicleType, @maximumCars, @maximumBikes, @allowMixedParking,
          @monthlyEnabled, @monthlyRent, @yearlyEnabled, @yearlyRent,
          @carMonthlyEnabled, @carMonthlyRent,
          @carYearlyEnabled, @carYearlyRent,
          @bikeMonthlyEnabled, @bikeMonthlyRent,
          @bikeYearlyEnabled, @bikeYearlyRent,
          @perVehiclePlans,
          @accessHours, @description, @conditions, @available, @autoApproval
        )
        RETURNING id
        '''),
        parameters: {
          'ownerId': ownerId,
          'parkingName': body['parkingName'].toString().trim(),
          'address': body['address'].toString().trim(),
          'city': _strOrNull(body['city']),
          'state': _strOrNull(body['state']),
          'pincode': _strOrNull(body['pincode']),
          'landmark': _strOrNull(body['landmark']),
          'latitude': (body['latitude'] as num).toDouble(),
          'longitude': (body['longitude'] as num).toDouble(),
          'parkingType': body['parkingType'].toString().toUpperCase(),
          'lengthM': (body['lengthM'] as num).toDouble(),
          'widthM': (body['widthM'] as num).toDouble(),
          'heightM': (body['heightM'] as num).toDouble(),
          'entranceLengthM': _numOrNull(body['entranceLengthM']),
          'entranceWidthM': _numOrNull(body['entranceWidthM']),
          'entranceHeightM': _numOrNull(body['entranceHeightM']),
          'vehicleType': body['vehicleType'].toString().toUpperCase(),
          'maximumCars': _intOrZero(body['maximumCars']),
          'maximumBikes': _intOrZero(body['maximumBikes']),
          'allowMixedParking': body['allowMixedParking'] == true,
          // The legacy pair is kept in sync (both vehicle types share it for
          // readers that predate migration 006); the per-vehicle columns are
          // what new readers and the booking flow actually use.
          'monthlyEnabled': plans.carMonthlyEnabled || plans.bikeMonthlyEnabled,
          'monthlyRent': plans.carMonthlyRent ?? plans.bikeMonthlyRent,
          'yearlyEnabled': plans.carYearlyEnabled || plans.bikeYearlyEnabled,
          'yearlyRent': plans.carYearlyRent ?? plans.bikeYearlyRent,
          'carMonthlyEnabled': plans.carMonthlyEnabled,
          'carMonthlyRent': plans.carMonthlyRent,
          'carYearlyEnabled': plans.carYearlyEnabled,
          'carYearlyRent': plans.carYearlyRent,
          'bikeMonthlyEnabled': plans.bikeMonthlyEnabled,
          'bikeMonthlyRent': plans.bikeMonthlyRent,
          'bikeYearlyEnabled': plans.bikeYearlyEnabled,
          'bikeYearlyRent': plans.bikeYearlyRent,
          'perVehiclePlans': true,
          'accessHours': body['accessHours']?.toString() ?? '24/7',
          'description': body['description']?.toString() ?? '',
          'conditions': body['conditions']?.toString() ?? '',
          'available': body['available'] != false,
          'autoApproval': body['autoApproval'] == true,
        },
      );
      final id = res.first.toColumnMap()['id']!.toString();

      await _replaceMedia(conn, id, photoUrls(body));
      await _replaceAmenities(conn, id, _stringList(body['amenities']));
      return id;
    });

    // The slot list is written after the listing exists (it has a FK), and
    // `replaceSpaces` re-derives maximum_cars / maximum_bikes from the real
    // rows so the two can never drift apart.
    await _spaces.replaceSpaces(parkingId: parkingId, spaces: spaces);

    return getById(parkingId, viewerId: ownerId);
  }

  // ---------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------
  Future<Map<String, dynamic>> getById(
    String parkingId, {
    String? viewerId,
    String? vehicleId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final row = await _fetchRow(parkingId);
    if (row == null) {
      throw ApiError.notFound('Parking listing not found.');
    }
    final owner = await _userName(row['owner_id'].toString());
    final photos = await _photosOf(parkingId);
    final amenities = await _amenitiesOf(parkingId);
    final spaceRows = await _spaces.listSpaces(parkingId);
    final vehicle = vehicleId == null ? null : await _vehicleRow(vehicleId);
    final vehicleType = vehicle?['vehicle_type']?.toString().toUpperCase();
    final vehicleLengthM = _numOrNull(vehicle?['length_m']);
    final vehicleWidthM = _numOrNull(vehicle?['width_m']);
    final vehicleHeightM = _numOrNull(vehicle?['height_m']);

    // Slot availability is ALWAYS computed for a real window, so the detail
    // screen can say "1 of 3 available" instead of the useless "3 total".
    //
    // * with a vehicle: the counts AND every per-slot `available` flag include
    //   the fit check (slot size + gate), so `available == false` means
    //   "booked, too small, or unreachable";
    // * without a vehicle: the per-type pools and the per-slot flags are still
    //   exact booked-vs-free, they just skip the fit part. The response marks
    //   that with `vehicleType: null`, which the client reads as "no verdict
    //   for a specific vehicle".
    final window = _window(startDate, endDate);
    final availability = await _spaces.availability(
      parkingId: parkingId,
      start: window.$1,
      end: window.$2,
      vehicleType: vehicleType,
      vehicleLengthM: vehicleLengthM,
      vehicleWidthM: vehicleWidthM,
      vehicleHeightM: vehicleHeightM,
    );
    final freeIds = await _spaces.freeSpaceIds(
      parkingId: parkingId,
      start: window.$1,
      end: window.$2,
      vehicleType: vehicleType,
      vehicleLengthM: vehicleLengthM,
      vehicleWidthM: vehicleWidthM,
      vehicleHeightM: vehicleHeightM,
    );
    final taken = await _spaces.bookedSpaceIds(parkingId, window.$1, window.$2);

    return parkingRowToJson(
      row,
      ownerName: owner,
      photoUrls: photos,
      amenities: amenities,
      spaces: spaceRows.map((s) {
        final id = s['id'].toString();
        return parkingSpaceRowToJson(
          s,
          available: freeIds.contains(id),
          booked: taken.wholeProperty || taken.ids.contains(id),
        );
      }).toList(),
      availability: availability,
    );
  }

  /// Individual spaces of one listing, each flagged available / not for the
  /// requested window so the user screen can render a real per-slot list.
  ///
  /// Without `vehicleId` the flags are still computed (booked vs free), they
  /// just ignore the "will my vehicle physically fit" part.
  Future<Map<String, dynamic>> spaces(
    String parkingId, {
    String? vehicleId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final row = await _fetchRow(parkingId);
    if (row == null) throw ApiError.notFound('Parking listing not found.');
    final vehicle = vehicleId == null ? null : await _vehicleRow(vehicleId);
    final window = _window(startDate, endDate);
    final availability = await _spaces.availability(
      parkingId: parkingId,
      start: window.$1,
      end: window.$2,
      vehicleType: vehicle?['vehicle_type']?.toString().toUpperCase(),
      vehicleLengthM: _numOrNull(vehicle?['length_m']),
      vehicleWidthM: _numOrNull(vehicle?['width_m']),
      vehicleHeightM: _numOrNull(vehicle?['height_m']),
    );
    final rows = await _spaces.listSpaces(parkingId);
    final availableIds = await _spaces.freeSpaceIds(
      parkingId: parkingId,
      start: window.$1,
      end: window.$2,
      vehicleType: vehicle?['vehicle_type']?.toString().toUpperCase(),
      vehicleLengthM: _numOrNull(vehicle?['length_m']),
      vehicleWidthM: _numOrNull(vehicle?['width_m']),
      vehicleHeightM: _numOrNull(vehicle?['height_m']),
    );
    final taken = await _spaces.bookedSpaceIds(parkingId, window.$1, window.$2);
    return {
      'parkingId': parkingId,
      'startDate': _dateOnly(window.$1),
      'endDate': _dateOnly(window.$2),
      'spaces': rows.map((s) {
        final id = s['id'].toString();
        return parkingSpaceRowToJson(
          s,
          available: availableIds.contains(id),
          booked: taken.wholeProperty || taken.ids.contains(id),
        );
      }).toList(),
      'availability': availability,
    };
  }

  Future<List<Map<String, dynamic>>> listByOwner(String ownerId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT * FROM parking_listings
        WHERE owner_id = @ownerId AND deleted_at IS NULL
        ORDER BY created_at DESC
        '''),
        parameters: {'ownerId': ownerId},
      );
    });
    final rows = res.map((r) => r.toColumnMap()).toList();
    final photosMap = await _photosFor(rows.map((r) => r['id'].toString()));
    final amenitiesMap = await _amenitiesFor(
      rows.map((r) => r['id'].toString()),
    );
    final spacesMap = await _spacesFor(rows.map((r) => r['id'].toString()));
    final utilisationMap = await _utilisationFor(
      rows.map((r) => r['id'].toString()),
    );
    final bookingsMap = await _currentBookingsFor(
      rows.map((r) => r['id'].toString()),
    );

    return rows.map((row) {
      final id = row['id'].toString();
      final booking = bookingsMap[id];
      return parkingRowToJson(
        row,
        ownerName: null,
        photoUrls: photosMap[id] ?? const [],
        amenities: amenitiesMap[id] ?? const [],
        currentBooking: booking,
        availableFrom: _availableFrom(booking),
        availableOverride: _effectiveAvailable(row, booking),
        spaces: _spaceJson(spacesMap[id]),
        utilisation: utilisationMap[id],
      );
    }).toList();
  }

  // ---------------------------------------------------------------------
  // Update / delete
  // ---------------------------------------------------------------------
  Future<Map<String, dynamic>> update({
    required String parkingId,
    required String ownerId,
    required Map<String, dynamic> body,
  }) async {
    final existing = await _fetchRow(parkingId);
    if (existing == null) throw ApiError.notFound('Parking listing not found.');
    if (existing['owner_id'].toString() != ownerId) {
      throw ApiError.forbidden('You can only edit your own parking listing.');
    }
    _validatePayload(body);
    final spaces = _spacesFrom(body);
    final plans = _plans(body);

    await Db.pool.withConnection((conn) async {
      await conn.execute(
        Sql.named('''
        UPDATE parking_listings SET
          parking_name = @parkingName, address = @address,
          city = @city, state = @state, pincode = @pincode, landmark = @landmark,
          latitude = @latitude, longitude = @longitude,
          parking_type = @parkingType,
          length_m = @lengthM, width_m = @widthM, height_m = @heightM,
          entrance_length_m = @entranceLengthM,
          entrance_width_m = @entranceWidthM,
          entrance_height_m = @entranceHeightM,
          allow_mixed_parking = @allowMixedParking,
          monthly_enabled = @monthlyEnabled, monthly_rent = @monthlyRent,
          yearly_enabled = @yearlyEnabled, yearly_rent = @yearlyRent,
          car_monthly_enabled = @carMonthlyEnabled,
          car_monthly_rent = @carMonthlyRent,
          car_yearly_enabled = @carYearlyEnabled,
          car_yearly_rent = @carYearlyRent,
          bike_monthly_enabled = @bikeMonthlyEnabled,
          bike_monthly_rent = @bikeMonthlyRent,
          bike_yearly_enabled = @bikeYearlyEnabled,
          bike_yearly_rent = @bikeYearlyRent,
          per_vehicle_plans = @perVehiclePlans,
          access_hours = @accessHours, description = @description,
          conditions = @conditions, available = @available,
          auto_approval = @autoApproval, updated_at = NOW()
        WHERE id = @id
        '''),
        parameters: {
          'id': parkingId,
          'parkingName': body['parkingName'].toString().trim(),
          'address': body['address'].toString().trim(),
          'city': _strOrNull(body['city']),
          'state': _strOrNull(body['state']),
          'pincode': _strOrNull(body['pincode']),
          'landmark': _strOrNull(body['landmark']),
          'latitude': (body['latitude'] as num).toDouble(),
          'longitude': (body['longitude'] as num).toDouble(),
          'parkingType': body['parkingType'].toString().toUpperCase(),
          'lengthM': (body['lengthM'] as num).toDouble(),
          'widthM': (body['widthM'] as num).toDouble(),
          'heightM': (body['heightM'] as num).toDouble(),
          'entranceLengthM': _numOrNull(body['entranceLengthM']),
          'entranceWidthM': _numOrNull(body['entranceWidthM']),
          'entranceHeightM': _numOrNull(body['entranceHeightM']),
          // vehicle_type / maximum_cars / maximum_bikes are re-derived from the
          // real slot rows by replaceSpaces() so they can never disagree.
          'allowMixedParking': body['allowMixedParking'] == true,
          // The legacy pair is kept in sync (both vehicle types share it for
          // readers that predate migration 006); the per-vehicle columns are
          // what new readers and the booking flow actually use.
          'monthlyEnabled': plans.carMonthlyEnabled || plans.bikeMonthlyEnabled,
          'monthlyRent': plans.carMonthlyRent ?? plans.bikeMonthlyRent,
          'yearlyEnabled': plans.carYearlyEnabled || plans.bikeYearlyEnabled,
          'yearlyRent': plans.carYearlyRent ?? plans.bikeYearlyRent,
          'carMonthlyEnabled': plans.carMonthlyEnabled,
          'carMonthlyRent': plans.carMonthlyRent,
          'carYearlyEnabled': plans.carYearlyEnabled,
          'carYearlyRent': plans.carYearlyRent,
          'bikeMonthlyEnabled': plans.bikeMonthlyEnabled,
          'bikeMonthlyRent': plans.bikeMonthlyRent,
          'bikeYearlyEnabled': plans.bikeYearlyEnabled,
          'bikeYearlyRent': plans.bikeYearlyRent,
          'perVehiclePlans': true,
          'accessHours': body['accessHours']?.toString() ?? '24/7',
          'description': body['description']?.toString() ?? '',
          'conditions': body['conditions']?.toString() ?? '',
          'available': body['available'] != false,
          'autoApproval': body['autoApproval'] == true,
        },
      );
      await _replaceMedia(conn, parkingId, photoUrls(body));
      await _replaceAmenities(conn, parkingId, _stringList(body['amenities']));
    });

    // Slot sync runs last: it can refuse the change (a booked slot may not be
    // removed) and it re-syncs the capacity columns.
    await _spaces.replaceSpaces(parkingId: parkingId, spaces: spaces);

    return getById(parkingId, viewerId: ownerId);
  }

  Future<void> delete({
    required String parkingId,
    required String ownerId,
  }) async {
    final existing = await _fetchRow(parkingId);
    if (existing == null) throw ApiError.notFound('Parking listing not found.');
    if (existing['owner_id'].toString() != ownerId) {
      throw ApiError.forbidden('You can only delete your own parking listing.');
    }
    await Db.pool.withConnection(
      (conn) => conn.execute(
        Sql.named('DELETE FROM parking_listings WHERE id = @id'),
        parameters: {'id': parkingId},
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Nearby (Haversine, metres-only fit fields, available listings only)
  // ---------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> nearby({
    required double lat,
    required double lng,
    double radiusKm = 5,
    String? vehicleId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw ApiError.validation(
        'Invalid coordinates: lat must be -90..90, lng -180..180.',
      );
    }
    if (radiusKm <= 0 || radiusKm > 100) {
      throw ApiError.validation('radiusKm must be between 0 and 100.');
    }

    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT * FROM parking_listings
        WHERE available = TRUE
          AND latitude IS NOT NULL AND longitude IS NOT NULL
          AND deleted_at IS NULL
        ORDER BY created_at DESC
        LIMIT 500
      '''),
        parameters: const {},
      );
    });

    final rows = res.map((r) => r.toColumnMap()).toList();
    final photosMap = await _photosFor(rows.map((r) => r['id'].toString()));
    final amenitiesMap = await _amenitiesFor(
      rows.map((r) => r['id'].toString()),
    );
    final spacesMap = await _spacesFor(rows.map((r) => r['id'].toString()));
    final vehicle = vehicleId == null ? null : await _vehicleRow(vehicleId);
    final availMap = await _availabilityForMany(
      rows.map((r) => r['id'].toString()).toList(),
      vehicle: vehicle,
      start: startDate,
      end: endDate,
    );

    final results = <Map<String, dynamic>>[];
    for (final row in rows) {
      final pLat = (row['latitude'] as num).toDouble();
      final pLng = (row['longitude'] as num).toDouble();
      final distance = _haversineKm(lat, lng, pLat, pLng);
      if (distance > radiusKm) continue;
      final id = row['id'].toString();
      results.add(
        parkingRowToJson(
          row,
          photoUrls: photosMap[id] ?? const [],
          amenities: amenitiesMap[id] ?? const [],
          distanceKm: double.parse(distance.toStringAsFixed(2)),
          spaces: _spaceJson(spacesMap[id]),
          availability: availMap[id],
        ),
      );
    }
    results.sort(
      (a, b) =>
          (a['distanceKm'] as double).compareTo(b['distanceKm'] as double),
    );
    return results;
  }

  // ---------------------------------------------------------------------
  // Shared validation
  // ---------------------------------------------------------------------
  void _validatePayload(Map<String, dynamic> body) {
    final name = body['parkingName']?.toString().trim() ?? '';
    final address = body['address']?.toString().trim() ?? '';
    if (name.isEmpty) throw ApiError.validation('Parking name is required.');
    if (name.length < 2) {
      throw ApiError.validation('Parking name must be at least 2 characters.');
    }
    if (address.isEmpty) throw ApiError.validation('Address is required.');

    final lat = body['latitude'];
    final lng = body['longitude'];
    if (lat is! num || lng is! num) {
      throw ApiError.validation('Latitude and longitude are mandatory.');
    }
    final latD = lat.toDouble();
    final lngD = lng.toDouble();
    if (latD < -90 || latD > 90 || lngD < -180 || lngD > 180) {
      throw ApiError.validation('Invalid latitude/longitude values.');
    }

    final parkingType = body['parkingType']?.toString().toUpperCase() ?? '';
    if (!ParkingType.all.contains(parkingType)) {
      throw ApiError.validation('Parking type must be NON_COVERED or COVERED.');
    }

    final lengthM = body['lengthM'];
    final widthM = body['widthM'];
    final heightM = body['heightM'];
    if (lengthM is! num || widthM is! num || heightM is! num) {
      throw ApiError.validation(
        'Parking dimensions (length, width, height in metres) are required.',
      );
    }
    if (lengthM <= 0 || widthM <= 0 || heightM <= 0) {
      throw ApiError.validation(
        'All parking dimensions must be greater than 0.',
      );
    }

    final vehicleType = body['vehicleType']?.toString().toUpperCase() ?? '';
    if (!ParkingVehicleType.all.contains(vehicleType)) {
      throw ApiError.validation('Vehicle type must be BIKE, CAR or BOTH.');
    }

    // Gate dimensions: width and height decide whether a vehicle can physically
    // get in, so both are required. Entrance length stays *optional* so listings
    // that were saved before it was collected keep working, but when the client
    // does send it the same "> 0" rule applies as for the plot dimensions.
    final entranceWidth = _numOrNull(body['entranceWidthM']);
    final entranceHeight = _numOrNull(body['entranceHeightM']);
    if (entranceWidth == null || entranceWidth <= 0) {
      throw ApiError.validation('Entrance width must be greater than 0.');
    }
    if (entranceHeight == null || entranceHeight <= 0) {
      throw ApiError.validation('Entrance height must be greater than 0.');
    }
    if (body['entranceLengthM'] != null) {
      final entranceLength = _numOrNull(body['entranceLengthM']);
      if (entranceLength == null || entranceLength <= 0) {
        throw ApiError.validation('Entrance length must be greater than 0.');
      }
    }

    final maximumCars = body['maximumCars'];
    final maximumBikes = body['maximumBikes'];
    if (maximumCars is! num || maximumCars < 0) {
      throw ApiError.validation('Maximum cars must be 0 or more.');
    }
    if (maximumBikes is! num || maximumBikes < 0) {
      throw ApiError.validation('Maximum bikes must be 0 or more.');
    }
    if (maximumCars < 1 && maximumBikes < 1) {
      throw ApiError.validation(
        'This parking needs at least one car space or one bike space.',
      );
    }

    final plans = _plans(body);
    if (!plans.carMonthlyEnabled &&
        !plans.carYearlyEnabled &&
        !plans.bikeMonthlyEnabled &&
        !plans.bikeYearlyEnabled) {
      throw ApiError.validation('At least one rental option must be enabled.');
    }
    void requireRent(bool enabled, double? rent, String message) {
      if (enabled && (rent == null || rent <= 0)) {
        throw ApiError.validation(message);
      }
    }

    if (_perVehiclePlans(body)) {
      requireRent(
        plans.carMonthlyEnabled,
        plans.carMonthlyRent,
        'Car monthly rent must be greater than 0 when enabled.',
      );
      requireRent(
        plans.carYearlyEnabled,
        plans.carYearlyRent,
        'Car yearly rent must be greater than 0 when enabled.',
      );
      requireRent(
        plans.bikeMonthlyEnabled,
        plans.bikeMonthlyRent,
        'Bike monthly rent must be greater than 0 when enabled.',
      );
      requireRent(
        plans.bikeYearlyEnabled,
        plans.bikeYearlyRent,
        'Bike yearly rent must be greater than 0 when enabled.',
      );
    } else {
      // Older client: one shared plan pair for both vehicle types.
      requireRent(
        plans.carMonthlyEnabled,
        plans.carMonthlyRent,
        'Monthly rent must be greater than 0 when enabled.',
      );
      requireRent(
        plans.carYearlyEnabled,
        plans.carYearlyRent,
        'Yearly rent must be greater than 0 when enabled.',
      );
    }

    final photos = photoUrls(body);
    if (photos.isEmpty) {
      throw ApiError.validation('At least one parking photo is required.');
    }
    if (photos.length > 4) {
      throw ApiError.validation(
        'You can upload a maximum of 4 parking photos.',
      );
    }

    final amenities = _stringList(body['amenities']);
    final known = ParkingAmenity.all;
    for (final a in amenities) {
      if (!known.contains(a)) {
        throw ApiError.validation('Unknown amenity: $a');
      }
    }
  }

  List<String> photoUrls(Map<String, dynamic> body) {
    final raw = body['photoUrls'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// The wizard's `spaces` array, normalised to the slot schema.
  ///
  /// When the client omits `spaces` (an older client, or a plain PUT from a
  /// third-party tool) a single slot is derived from the listing dimensions so
  /// the parking stays bookable instead of silently losing all capacity.
  List<Map<String, dynamic>> _spacesFrom(Map<String, dynamic> body) {
    final raw = body['spaces'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    final lengthM = _numOrNull(body['lengthM']) ?? 5.0;
    final widthM = _numOrNull(body['widthM']) ?? 2.5;
    final heightM = _numOrNull(body['heightM']) ?? 2.2;
    final vehicleType = body['vehicleType']?.toString().toUpperCase() ?? '';
    final spaces = <Map<String, dynamic>>[];
    if (vehicleType == ParkingVehicleType.car ||
        vehicleType == ParkingVehicleType.both) {
      spaces.add({
        'spaceCode': 'C1',
        'spaceName': 'Car Space 1',
        'vehicleType': ParkingVehicleType.car,
        'lengthM': lengthM,
        'widthM': widthM,
        'heightM': heightM,
      });
    }
    if (vehicleType == ParkingVehicleType.bike ||
        vehicleType == ParkingVehicleType.both) {
      spaces.add({
        'spaceCode': 'B1',
        'spaceName': 'Bike Space 1',
        'vehicleType': ParkingVehicleType.bike,
        'lengthM': lengthM,
        'widthM': widthM,
        'heightM': heightM,
      });
    }
    return spaces;
  }

  /// Slot lists for many parkings, grouped by parking id (one query).
  Future<Map<String, List<Map<String, dynamic>>>> _spacesFor(
    Iterable<String> ids,
  ) async {
    final list = ids.toList();
    if (list.isEmpty) return {};
    final placeholders = List.generate(list.length, (i) => '@id$i').join(', ');
    final params = <String, Object?>{
      for (var i = 0; i < list.length; i++) 'id$i': list[i],
    };
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT * FROM parking_spaces
        WHERE parking_id IN ($placeholders) AND is_active = TRUE
        ORDER BY vehicle_type ASC, space_code ASC
        '''),
        parameters: params,
      );
    });
    final map = <String, List<Map<String, dynamic>>>{};
    for (final r in res) {
      final row = r.toColumnMap();
      map.putIfAbsent(row['parking_id'].toString(), () => []).add(row);
    }
    return map;
  }

  /// Raw `parking_spaces` rows -> API JSON. The raw rows carry Postgres
  /// `DateTime` values (created_at / updated_at) which `jsonEncode` cannot
  /// serialise, so they are always converted before being handed to a
  /// response.
  List<Map<String, dynamic>> _spaceJson(List<Map<String, dynamic>>? rows) =>
      (rows ?? const []).map(parkingSpaceRowToJson).toList();

  /// Owner utilisation for many parkings, grouped by parking id.
  Future<Map<String, Map<String, dynamic>>> _utilisationFor(
    Iterable<String> ids,
  ) async {
    final out = <String, Map<String, dynamic>>{};
    for (final id in ids) {
      out[id] = await _spaces.utilisation(id);
    }
    return out;
  }

  /// Slot availability for a single parking. Null when the caller did not ask
  /// for a vehicle/date window (the payload is then omitted entirely).
  Future<Map<String, dynamic>?> _availabilityFor({
    required String parkingId,
    required Map<String, dynamic>? vehicle,
    DateTime? start,
    DateTime? end,
  }) async {
    if (vehicle == null) return null;
    final window = _window(start, end);
    return _spaces.availability(
      parkingId: parkingId,
      start: window.$1,
      end: window.$2,
      vehicleType: vehicle['vehicle_type']?.toString().toUpperCase(),
      vehicleLengthM: _numOrNull(vehicle['length_m']),
      vehicleWidthM: _numOrNull(vehicle['width_m']),
      vehicleHeightM: _numOrNull(vehicle['height_m']),
    );
  }

  Future<Map<String, Map<String, dynamic>>> _availabilityForMany(
    List<String> ids, {
    required Map<String, dynamic>? vehicle,
    DateTime? start,
    DateTime? end,
  }) async {
    if (vehicle == null) return const {};
    final window = _window(start, end);
    final out = <String, Map<String, dynamic>>{};
    for (final id in ids) {
      final availability = await _availabilityFor(
        parkingId: id,
        vehicle: vehicle,
        start: window.$1,
        end: window.$2,
      );
      if (availability != null) out[id] = availability;
    }
    return out;
  }

  /// Availability window. The map has no date picker, so it defaults to today
  /// (a park is "available now" when it has a free slot today).
  (DateTime, DateTime) _window(DateTime? start, DateTime? end) {
    final today = DateTime.now();
    final s = start ?? today;
    final e = end ?? (start == null ? today : s);
    return (s, e.isBefore(s) ? s : e);
  }

  Future<Map<String, dynamic>?> _vehicleRow(String id) async {
    if (!isUuid(id)) return null;
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT * FROM vehicles WHERE id = @id'),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------
  List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final e in raw) {
      final s = e.toString().trim();
      if (s.isNotEmpty) out.add(s);
    }
    return out;
  }

  String? _strOrNull(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  double? _numOrNull(Object? v) => v is num ? v.toDouble() : null;

  int _intOrZero(Object? v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  /// True when the client speaks the per-vehicle plan scheme (any car/bike
  /// plan key in the body). Older clients only send the legacy pair.
  bool _perVehiclePlans(Map<String, dynamic> body) =>
      body.containsKey('carMonthlyEnabled') ||
      body.containsKey('carYearlyEnabled') ||
      body.containsKey('bikeMonthlyEnabled') ||
      body.containsKey('bikeYearlyEnabled');

  /// The four independent rental plans, normalised.
  ///
  /// A new client sends each plan (car/bike x monthly/yearly) on its own. An
  /// older client only sends `monthlyEnabled`/`monthlyRent` and the yearly
  /// pair, which is then shared by BOTH vehicle types — exactly how it
  /// behaved before migration 006.
  ///
  /// Disabled plans resolve to a `null` rent: `parking_listings` carries
  /// `CHECK (car_monthly_rent IS NULL OR car_monthly_rent > 0)` (and the same
  /// for the other three), so storing 0 for a switched-off plan would fail
  /// the constraint and surface as a 500. `_validatePayload` has already
  /// rejected an enabled plan with a non-positive rent.
  ({
    bool carMonthlyEnabled,
    double? carMonthlyRent,
    bool carYearlyEnabled,
    double? carYearlyRent,
    bool bikeMonthlyEnabled,
    double? bikeMonthlyRent,
    bool bikeYearlyEnabled,
    double? bikeYearlyRent,
  })
  _plans(Map<String, dynamic> body) {
    double? asRent(Object? v) => v is num ? v.toDouble() : null;

    if (!_perVehiclePlans(body)) {
      final monthlyEnabled = body['monthlyEnabled'] == true;
      final yearlyEnabled = body['yearlyEnabled'] == true;
      final monthlyRent = monthlyEnabled ? asRent(body['monthlyRent']) : null;
      final yearlyRent = yearlyEnabled ? asRent(body['yearlyRent']) : null;
      return (
        carMonthlyEnabled: monthlyEnabled,
        carMonthlyRent: monthlyRent,
        carYearlyEnabled: yearlyEnabled,
        carYearlyRent: yearlyRent,
        bikeMonthlyEnabled: monthlyEnabled,
        bikeMonthlyRent: monthlyRent,
        bikeYearlyEnabled: yearlyEnabled,
        bikeYearlyRent: yearlyRent,
      );
    }

    bool on(String key) => body[key] == true;
    double? rent(String enabledKey, String rentKey) =>
        on(enabledKey) ? asRent(body[rentKey]) : null;
    return (
      carMonthlyEnabled: on('carMonthlyEnabled'),
      carMonthlyRent: rent('carMonthlyEnabled', 'carMonthlyRent'),
      carYearlyEnabled: on('carYearlyEnabled'),
      carYearlyRent: rent('carYearlyEnabled', 'carYearlyRent'),
      bikeMonthlyEnabled: on('bikeMonthlyEnabled'),
      bikeMonthlyRent: rent('bikeMonthlyEnabled', 'bikeMonthlyRent'),
      bikeYearlyEnabled: on('bikeYearlyEnabled'),
      bikeYearlyRent: rent('bikeYearlyEnabled', 'bikeYearlyRent'),
    );
  }

  /// `YYYY-MM-DD` (dates are compared as calendar days in the slot engine).
  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// True when [id] is a well-formed UUID (all `id` columns use `uuid`).
  static bool isUuid(String id) => _uuidPattern.hasMatch(id);
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  Future<Map<String, dynamic>?> _fetchRow(String id) async {
    // `id` is a UUID column: a malformed value is "not found" rather than a
    // Postgres "invalid input syntax for type uuid" 500.
    if (!isUuid(id)) return null;
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named(
          'SELECT * FROM parking_listings WHERE id = @id AND deleted_at IS NULL',
        ),
        parameters: {'id': id},
      );
    });
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  Future<String> _userName(String userId) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('SELECT name FROM users WHERE id = @id'),
        parameters: {'id': userId},
      );
    });
    if (res.isEmpty) return '';
    return res.first.toColumnMap()['name']?.toString() ?? '';
  }

  Future<List<String>> _photosOf(String id) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT url FROM parking_media WHERE parking_id = @id
        ORDER BY display_order ASC'''),
        parameters: {'id': id},
      );
    });
    return res.map((r) => r.toColumnMap()['url'].toString()).toList();
  }

  Future<List<String>> _amenitiesOf(String id) async {
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named(
          'SELECT amenity FROM parking_amenities WHERE parking_id = @id',
        ),
        parameters: {'id': id},
      );
    });
    return res.map((r) => r.toColumnMap()['amenity'].toString()).toList();
  }

  Future<Map<String, List<String>>> _photosFor(Iterable<String> ids) =>
      _collectChild(ids, 'parking_media', 'url', 'display_order', 'url');

  Future<Map<String, List<String>>> _amenitiesFor(Iterable<String> ids) =>
      _collectChild(ids, 'parking_amenities', 'amenity', null, 'amenity');

  /// Groups child values by parent parking id using one IN query.
  Future<Map<String, List<String>>> _collectChild(
    Iterable<String> ids,
    String table,
    String valueCol,
    String? orderCol,
    String outKey,
  ) async {
    final list = ids.toList();
    if (list.isEmpty) return {};
    final placeholders = List.generate(list.length, (i) => '@id$i').join(', ');
    final params = <String, Object?>{
      for (var i = 0; i < list.length; i++) 'id$i': list[i],
    };
    final order = orderCol == null ? '' : ' ORDER BY $orderCol ASC';
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named(
          'SELECT parking_id, $valueCol AS v FROM $table WHERE parking_id IN ($placeholders)$order',
        ),
        parameters: params,
      );
    });
    final map = <String, List<String>>{};
    for (final r in res) {
      final row = r.toColumnMap();
      final pid = row['parking_id'].toString();
      map.putIfAbsent(pid, () => []).add(row['v'].toString());
    }
    return map;
  }

  /// Most recent occupying booking (dates overlapping or after today).
  Future<Map<String, Map<String, dynamic>>> _currentBookingsFor(
    Iterable<String> ids,
  ) async {
    final list = ids.toList();
    if (list.isEmpty) return {};
    final placeholders = List.generate(list.length, (i) => '@id$i').join(', ');
    final params = <String, Object?>{
      for (var i = 0; i < list.length; i++) 'id$i': list[i],
    };
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT DISTINCT ON (parking_id) *
        FROM bookings
        WHERE parking_id IN ($placeholders)
          AND status = ANY(ARRAY['ACCEPTED','PAYMENT_PENDING','CONFIRMED','ACTIVE'])
          AND end_date >= CURRENT_DATE
        ORDER BY parking_id, start_date ASC
        '''),
        parameters: params,
      );
    });
    final map = <String, Map<String, dynamic>>{};
    for (final r in res) {
      final row = r.toColumnMap();
      map[row['parking_id'].toString()] = bookingCoreJson(row);
    }
    return map;
  }

  /// Derived dashboard fields: availability + next free date.
  bool _effectiveAvailable(Map<String, dynamic> row, Map<String, dynamic>? b) =>
      row['available'] == true && b == null;

  String? _availableFrom(Map<String, dynamic>? booking) {
    if (booking == null) return null;
    final endRaw = booking['endDate']?.toString();
    if (endRaw == null || endRaw.isEmpty) return null;
    final end = DateTime.tryParse(endRaw);
    if (end == null) return null;
    final next = end.add(const Duration(days: 1));
    return '${next.year.toString().padLeft(4, '0')}-'
        '${next.month.toString().padLeft(2, '0')}-'
        '${next.day.toString().padLeft(2, '0')}';
  }

  Future<void> _replaceMedia(
    dynamic conn,
    String parkingId,
    List<String> urls,
  ) async {
    await conn.execute(
      Sql.named('DELETE FROM parking_media WHERE parking_id = @id'),
      parameters: {'id': parkingId},
    );
    for (var i = 0; i < urls.length; i++) {
      await conn.execute(
        Sql.named('''
        INSERT INTO parking_media (parking_id, media_type, url, display_order)
        VALUES (@pid, 'PHOTO', @url, @order)
        '''),
        parameters: {'pid': parkingId, 'url': urls[i], 'order': i},
      );
    }
  }

  Future<void> _replaceAmenities(
    dynamic conn,
    String parkingId,
    List<String> amenities,
  ) async {
    await conn.execute(
      Sql.named('DELETE FROM parking_amenities WHERE parking_id = @id'),
      parameters: {'id': parkingId},
    );
    for (final a in amenities) {
      await conn.execute(
        Sql.named('''
        INSERT INTO parking_amenities (parking_id, amenity) VALUES (@pid, @a)
        '''),
        parameters: {'pid': parkingId, 'a': a},
      );
    }
  }

  /// Great-circle distance between two coordinates (kilometres).
  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0;
    double rad(double d) => d * (pi / 180.0);
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a =
        pow(sin(dLat / 2), 2) +
        cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLon / 2), 2);
    return 2 * r * asin(sqrt(a));
  }
}
