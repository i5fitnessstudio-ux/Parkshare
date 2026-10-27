import 'package:parkshare_backend/database/db.dart';
import 'package:parkshare_backend/middleware/middleware.dart';
import 'package:parkshare_backend/models/booking.dart';
import 'package:parkshare_backend/models/parking.dart';
import 'package:parkshare_backend/models/parking_space.dart';
import 'package:postgres/postgres.dart';

/// Why a slot could not be allocated. Lets the caller pick the exact customer
/// message instead of leaking a generic "unavailable".
enum SlotOutcome {
  /// A suitable, free slot was found.
  allocated,

  /// The parking has no slot of this vehicle type, or none of them is big
  /// enough for the vehicle / its gate is too tight.
  noFit,

  /// Slots exist and fit, but every one of them is already booked for the
  /// requested date range.
  full,
}

/// Result of the slot search inside one date window.
class SlotAllocation {
  final SlotOutcome outcome;
  final Map<String, dynamic>? space;
  final int totalSpaces;
  final int freeSpaces;

  const SlotAllocation({
    required this.outcome,
    required this.totalSpaces,
    required this.freeSpaces,
    this.space,
  });

  bool get isAllocated => outcome == SlotOutcome.allocated;
}

/// Slot-based parking capacity: the individual physical spaces, their
/// date-aware availability and the allocation a new booking is bound to.
///
/// Core rule: a booking holds exactly ONE slot. One booked slot never blocks
/// the rest of the property.
class ParkingSpaceService {
  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------
  /// All slots of a parking, ordered car-then-bike, then by code.
  /// Pass [conn] to read through an open transaction instead of the pool.
  Future<List<Map<String, dynamic>>> listSpaces(
    String parkingId, {
    bool activeOnly = true,
    dynamic conn,
  }) async {
    if (!isUuid(parkingId)) return const [];
    Future<Result> run(dynamic c) => c.execute(
      Sql.named('''
      SELECT * FROM parking_spaces
      WHERE parking_id = @id
        ${activeOnly ? 'AND is_active = TRUE' : ''}
      ORDER BY vehicle_type ASC, space_code ASC
      '''),
      parameters: {'id': parkingId},
    );
    final res = conn != null
        ? await run(conn)
        : await Db.pool.withConnection(run);
    return res.map((r) => r.toColumnMap()).toList();
  }

  /// Active-slot counts per vehicle type for many parkings in one pass.
  Future<Map<String, Map<String, int>>> countsFor(Iterable<String> ids) async {
    final list = ids.toList();
    final out = <String, Map<String, int>>{};
    if (list.isEmpty) return out;
    final placeholders = List.generate(list.length, (i) => '@id$i').join(', ');
    final params = <String, Object?>{
      for (var i = 0; i < list.length; i++) 'id$i': list[i],
    };
    final res = await Db.pool.withConnection((conn) async {
      return conn.execute(
        Sql.named('''
        SELECT parking_id, vehicle_type, COUNT(*) AS total
        FROM parking_spaces
        WHERE parking_id IN ($placeholders) AND is_active = TRUE
        GROUP BY parking_id, vehicle_type
        '''),
        parameters: params,
      );
    });
    for (final r in res) {
      final row = r.toColumnMap();
      final pid = row['parking_id'].toString();
      final bucket = out.putIfAbsent(pid, () => {'CAR': 0, 'BIKE': 0});
      bucket[row['vehicle_type'].toString()] =
          int.tryParse('${row['total']}') ?? 0;
    }
    return out;
  }

  /// Ids of the slots that are genuinely free for the window, taking the
  /// vehicle fit and the gate into account. Used to render a per-slot
  /// available/not-available list on the user screens.
  Future<Set<String>> freeSpaceIds({
    required String parkingId,
    required DateTime start,
    required DateTime end,
    String? vehicleType,
    double? vehicleLengthM,
    double? vehicleWidthM,
    double? vehicleHeightM,
    dynamic conn,
  }) async {
    final parking = await _parkingRow(parkingId, conn: conn);
    if (parking == null) return {};
    final spaces = await listSpaces(parkingId, conn: conn);
    final taken = await _occupiedSpaceIds(parkingId, start, end, conn: conn);
    if (taken.legacy) return {};
    final entranceW = _num(parking['entrance_width_m']);
    final entranceH = _num(parking['entrance_height_m']);
    final hasDims =
        vehicleLengthM != null &&
        vehicleWidthM != null &&
        vehicleHeightM != null;
    final type = vehicleType?.toUpperCase();
    return spaces
        .where(
          (s) =>
              !taken.ids.contains(s['id'].toString()) &&
              (type == null || s['vehicle_type'] == type) &&
              (!hasDims ||
                  _fitsSpace(
                    space: s,
                    vehicleLengthM: vehicleLengthM,
                    vehicleWidthM: vehicleWidthM,
                    vehicleHeightM: vehicleHeightM,
                    entranceWidthM: entranceW,
                    entranceHeightM: entranceH,
                  )),
        )
        .map((s) => s['id'].toString())
        .toSet();
  }

  /// Slots held by an occupying booking that overlaps the window.
  ///
  /// Purely date-based: no vehicle fit and no gate check. This is the factual
  /// "is this bay already taken for these dates" answer, so the client can say
  /// *Booked* rather than guessing why a slot is not bookable. A legacy
  /// (slot-less) booking holds the whole property, so every slot reports booked.
  Future<({Set<String> ids, bool wholeProperty})> bookedSpaceIds(
    String parkingId,
    DateTime start,
    DateTime end, {
    dynamic conn,
  }) async {
    final taken = await _occupiedSpaceIds(parkingId, start, end, conn: conn);
    return (
      ids: taken.legacy ? <String>{} : taken.ids,
      wholeProperty: taken.legacy,
    );
  }

  // ---------------------------------------------------------------------
  // Availability (slot + date range)
  // ---------------------------------------------------------------------
  /// Availability for one parking, one date window and (optionally) one
  /// vehicle. This is what the user map, the parking detail sheet and the
  /// booking form all read — no hardcoded numbers anywhere.
  ///
  /// Legacy bookings created before slot allocation (parking_space_id IS NULL)
  /// are treated as holding the WHOLE property for overlapping dates, which is
  /// exactly how they behaved before the migration.
  Future<Map<String, dynamic>> availability({
    required String parkingId,
    required DateTime start,
    required DateTime end,
    String? vehicleType,
    double? vehicleLengthM,
    double? vehicleWidthM,
    double? vehicleHeightM,
  }) async {
    final parking = await _parkingRow(parkingId);
    if (parking == null) {
      throw ApiError.notFound('Parking listing not found.');
    }

    final spaces = await listSpaces(parkingId);
    final taken = await _occupiedSpaceIds(parkingId, start, end, conn: null);
    final legacyBlock = taken.legacy;

    final carSpaces = spaces
        .where((s) => s['vehicle_type'] == ParkingVehicleType.car)
        .toList();
    final bikeSpaces = spaces
        .where((s) => s['vehicle_type'] == ParkingVehicleType.bike)
        .toList();

    bool free(Map<String, dynamic> s) =>
        !legacyBlock && !taken.ids.contains(s['id'].toString());

    final carAvailable = carSpaces.where(free).length;
    final bikeAvailable = bikeSpaces.where(free).length;

    final entranceW = _num(parking['entrance_width_m']);
    final entranceH = _num(parking['entrance_height_m']);
    final hasDims =
        vehicleLengthM != null &&
        vehicleWidthM != null &&
        vehicleHeightM != null;

    int fit(List<Map<String, dynamic>> pool) {
      if (!hasDims) return pool.where(free).length;
      return pool
          .where(
            (s) =>
                free(s) &&
                _fitsSpace(
                  space: s,
                  vehicleLengthM: vehicleLengthM,
                  vehicleWidthM: vehicleWidthM,
                  vehicleHeightM: vehicleHeightM,
                  entranceWidthM: entranceW,
                  entranceHeightM: entranceH,
                ),
          )
          .length;
    }

    final type = vehicleType?.toUpperCase();
    final List<Map<String, dynamic>> pool = switch (type) {
      ParkingSpaceVehicleType.bike => bikeSpaces,
      ParkingSpaceVehicleType.car => carSpaces,
      _ => const <Map<String, dynamic>>[],
    };

    final availableSpaces = type == null ? 0 : fit(pool);
    final totalForType = type == null ? 0 : pool.length;
    // True when at least one slot of this type could physically take the
    // vehicle, regardless of bookings. Distinguishes "full" from "too small".
    final fitsAnywhere = type == null
        ? false
        : (hasDims
                  ? pool
                        .where(
                          (s) => _fitsSpace(
                            space: s,
                            vehicleLengthM: vehicleLengthM,
                            vehicleWidthM: vehicleWidthM,
                            vehicleHeightM: vehicleHeightM,
                            entranceWidthM: entranceW,
                            entranceHeightM: entranceH,
                          ),
                        )
                        .length
                  : pool.length) >
              0;

    return {
      'parkingId': parkingId,
      'startDate': _dateOnly(start),
      'endDate': _dateOnly(end),
      'vehicleType': type,
      'totalSpaces': totalForType,
      'availableSpaces': availableSpaces,
      'isAvailable': availableSpaces > 0,
      'fitsAnySpace': fitsAnywhere,
      'blockingStatuses': occupyingStatusList,
      'legacyParkingBlocked': legacyBlock,
      'carSpaces': {'total': carSpaces.length, 'available': carAvailable},
      'bikeSpaces': {'total': bikeSpaces.length, 'available': bikeAvailable},
    };
  }

  // ---------------------------------------------------------------------
  // Allocation
  // ---------------------------------------------------------------------
  /// Finds the slot a new booking should take. Runs on the caller's
  /// connection (pass `tx` inside a transaction) so the overlap re-check and
  /// the INSERT are atomic.
  ///
  /// Order of preference: a free slot that fits. When nothing free fits, the
  /// result is [SlotOutcome.noFit] so the user is told the vehicle may not fit
  /// this parking space — a slot is never silently over-committed.
  ///
  /// [preferredSpaceId] keeps a booking on the slot it was already promised
  /// (accept-time re-verification) when that slot is still free and big enough;
  /// it never forces an unsuitable slot.
  Future<SlotAllocation> allocate({
    required String parkingId,
    required String vehicleType,
    required double vehicleLengthM,
    required double vehicleWidthM,
    required double vehicleHeightM,
    required DateTime start,
    required DateTime end,
    String? preferredSpaceId,
    dynamic conn,
  }) async {
    final spaces = await listSpaces(parkingId, conn: conn);
    if (spaces.isEmpty) {
      return const SlotAllocation(
        outcome: SlotOutcome.noFit,
        totalSpaces: 0,
        freeSpaces: 0,
      );
    }
    final pool = spaces.where((s) => s['vehicle_type'] == vehicleType).toList();
    if (pool.isEmpty) {
      return SlotAllocation(
        outcome: SlotOutcome.noFit,
        totalSpaces: 0,
        freeSpaces: 0,
      );
    }

    final taken = await _occupiedSpaceIds(parkingId, start, end, conn: conn);
    if (taken.legacy) {
      return SlotAllocation(
        outcome: SlotOutcome.full,
        totalSpaces: pool.length,
        freeSpaces: 0,
      );
    }

    final parking = await _parkingRow(parkingId, conn: conn);
    final entranceW = _num(parking?['entrance_width_m']);
    final entranceH = _num(parking?['entrance_height_m']);
    final free = pool
        .where((s) => !taken.ids.contains(s['id'].toString()))
        .toList();

    if (preferredSpaceId != null && preferredSpaceId.isNotEmpty) {
      for (final s in free) {
        if (s['id'].toString() == preferredSpaceId &&
            _fitsSpace(
              space: s,
              vehicleLengthM: vehicleLengthM,
              vehicleWidthM: vehicleWidthM,
              vehicleHeightM: vehicleHeightM,
              entranceWidthM: entranceW,
              entranceHeightM: entranceH,
            )) {
          return SlotAllocation(
            outcome: SlotOutcome.allocated,
            totalSpaces: pool.length,
            freeSpaces: free.length,
            space: s,
          );
        }
      }
    }

    for (final s in free) {
      if (_fitsSpace(
        space: s,
        vehicleLengthM: vehicleLengthM,
        vehicleWidthM: vehicleWidthM,
        vehicleHeightM: vehicleHeightM,
        entranceWidthM: entranceW,
        entranceHeightM: entranceH,
      )) {
        return SlotAllocation(
          outcome: SlotOutcome.allocated,
          totalSpaces: pool.length,
          freeSpaces: free.length,
          space: s,
        );
      }
    }

    return SlotAllocation(
      outcome: free.isEmpty ? SlotOutcome.full : SlotOutcome.noFit,
      totalSpaces: pool.length,
      freeSpaces: free.length,
    );
  }

  // ---------------------------------------------------------------------
  // Owner writes
  // ---------------------------------------------------------------------
  /// Replaces the slot configuration of a parking from the wizard payload.
  ///
  /// * slots carrying an active/upcoming occupying booking are never removed
  /// * `maximumCars` / `maximumBikes` are kept consistent with the slot list
  Future<void> replaceSpaces({
    required String parkingId,
    required List<Map<String, dynamic>> spaces,
  }) async {
    if (spaces.isEmpty) {
      throw ApiError.validation('Add at least one parking space.');
    }

    final existing = await listSpaces(parkingId, activeOnly: false);
    final existingByCode = <String, Map<String, dynamic>>{
      for (final s in existing) s['space_code'].toString(): s,
    };

    final codes = <String>{};
    for (final raw in spaces) {
      final code = (raw['spaceCode']?.toString() ?? '').trim().toUpperCase();
      if (code.isEmpty) {
        throw ApiError.validation('Every parking space needs a code.');
      }
      if (code.length > 24) {
        throw ApiError.validation(
          'Parking space codes can be at most 24 characters.',
        );
      }
      if (!codes.add(code)) {
        throw ApiError.validation('Duplicate parking space code "$code".');
      }
      final vt = (raw['vehicleType']?.toString() ?? '').toUpperCase();
      if (!ParkingSpaceVehicleType.all.contains(vt)) {
        throw ApiError.validation('Parking space type must be BIKE or CAR.');
      }
      final l = _num(raw['lengthM']);
      final w = _num(raw['widthM']);
      final h = _num(raw['heightM']);
      if (l == null || l <= 0 || w == null || w <= 0 || h == null || h <= 0) {
        throw ApiError.validation(
          'Every parking space needs a length, width and height greater than 0.',
        );
      }
    }

    await Db.pool.withConnection((conn) async {
      // Slots referenced by an occupying booking may not disappear.
      final removed = existing.where(
        (s) => !codes.contains(s['space_code'].toString()),
      );
      for (final s in removed) {
        final busy = await _hasActiveBooking(conn, s['id'].toString());
        if (busy) {
          throw ApiError.conflict(
            'This parking space has an active or upcoming booking and '
            'cannot be removed.',
          );
        }
      }
      for (final s in existing) {
        if (codes.contains(s['space_code'].toString())) continue;
        await conn.execute(
          Sql.named('DELETE FROM parking_spaces WHERE id = @id'),
          parameters: {'id': s['id'].toString()},
        );
      }

      for (final raw in spaces) {
        final code = (raw['spaceCode']?.toString() ?? '').trim().toUpperCase();
        final name = (raw['spaceName']?.toString() ?? '').trim().isEmpty
            ? null
            : raw['spaceName'].toString().trim();
        // Kept separate: `@code` only exists in the INSERT, and passing an
        // unused named parameter to a query is a hard Postgres error.
        final values = {
          'name': name,
          'vt': (raw['vehicleType']?.toString() ?? '').toUpperCase(),
          'l': _num(raw['lengthM'])!,
          'w': _num(raw['widthM'])!,
          'h': _num(raw['heightM'])!,
        };
        final prev = existingByCode[code];
        if (prev != null) {
          await conn.execute(
            Sql.named('''
            UPDATE parking_spaces SET
              space_name = @name, vehicle_type = @vt,
              length_m = @l, width_m = @w, height_m = @h,
              is_active = TRUE, updated_at = NOW()
            WHERE id = @id
            '''),
            parameters: {'id': prev['id'].toString(), ...values},
          );
        } else {
          await conn.execute(
            Sql.named('''
            INSERT INTO parking_spaces
              (parking_id, space_code, space_name, vehicle_type,
               length_m, width_m, height_m)
            VALUES (@parkingId, @code, @name, @vt, @l, @w, @h)
            '''),
            parameters: {'parkingId': parkingId, 'code': code, ...values},
          );
        }
      }

      // Capacity mirrors the real slot counts so the numbers can never drift.
      final counts = await conn.execute(
        Sql.named('''
        SELECT vehicle_type, COUNT(*) AS total FROM parking_spaces
        WHERE parking_id = @parkingId AND is_active = TRUE
        GROUP BY vehicle_type
        '''),
        parameters: {'parkingId': parkingId},
      );
      var cars = 0;
      var bikes = 0;
      for (final r in counts) {
        final row = r.toColumnMap();
        final n = int.tryParse('${row['total']}') ?? 0;
        if (row['vehicle_type'] == ParkingSpaceVehicleType.car) {
          cars = n;
        } else {
          bikes = n;
        }
      }
      if (cars == 0 && bikes == 0) {
        throw ApiError.validation(
          'This parking needs at least one car or bike space.',
        );
      }
      await conn.execute(
        Sql.named('''
        UPDATE parking_listings
        SET maximum_cars = @cars, maximum_bikes = @bikes,
            vehicle_type = @vehicleType, updated_at = NOW()
        WHERE id = @parkingId
        '''),
        parameters: {
          'parkingId': parkingId,
          'cars': cars,
          'bikes': bikes,
          'vehicleType': cars > 0 && bikes > 0
              ? ParkingVehicleType.both
              : cars > 0
              ? ParkingVehicleType.car
              : ParkingVehicleType.bike,
        },
      );
    });
  }

  /// Owner-facing utilisation: how many slots are taken right now (or by an
  /// upcoming occupying booking) per vehicle type.
  Future<Map<String, dynamic>> utilisation(String parkingId) async {
    final parking = await _parkingRow(parkingId);
    if (parking == null) {
      throw ApiError.notFound('Parking listing not found.');
    }
    final spaces = await listSpaces(parkingId);
    final taken = await _occupiedSpaceIds(
      parkingId,
      DateTime.now(),
      DateTime.now().add(const Duration(days: 3650)),
    );
    final blocked = taken.legacy
        ? spaces.map((s) => s['id'].toString()).toSet()
        : taken.ids;

    int countOf(String type) =>
        spaces.where((s) => s['vehicle_type'] == type).length;
    int busyOf(String type) => spaces
        .where(
          (s) =>
              s['vehicle_type'] == type && blocked.contains(s['id'].toString()),
        )
        .length;

    final carTotal = countOf(ParkingVehicleType.car);
    final bikeTotal = countOf(ParkingVehicleType.bike);
    return {
      'parkingId': parkingId,
      'carSpaces': {
        'total': carTotal,
        'occupied': busyOf(ParkingVehicleType.car),
        'available': carTotal - busyOf(ParkingVehicleType.car),
      },
      'bikeSpaces': {
        'total': bikeTotal,
        'occupied': busyOf(ParkingVehicleType.bike),
        'available': bikeTotal - busyOf(ParkingVehicleType.bike),
      },
    };
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------
  /// A vehicle fits a slot when every dimension is <= the slot's, and the
  /// gate is wide/tall enough to get in. Plain numeric comparison, no strings.
  static bool _fitsSpace({
    required Map<String, dynamic> space,
    required double vehicleLengthM,
    required double vehicleWidthM,
    required double vehicleHeightM,
    double? entranceWidthM,
    double? entranceHeightM,
  }) {
    final sl = _num(space['length_m']);
    final sw = _num(space['width_m']);
    final sh = _num(space['height_m']);
    if (sl == null || sw == null || sh == null) return false;
    if (vehicleLengthM > sl) return false;
    if (vehicleWidthM > sw) return false;
    if (vehicleHeightM > sh) return false;
    // A missing gate dimension cannot block a booking (legacy listings).
    if (entranceWidthM != null && vehicleWidthM > entranceWidthM) return false;
    if (entranceHeightM != null && vehicleHeightM > entranceHeightM) {
      return false;
    }
    return true;
  }

  Future<bool> _hasActiveBooking(dynamic conn, String spaceId) async {
    final res = await conn.execute(
      Sql.named('''
      SELECT 1 FROM bookings
      WHERE parking_space_id = @spaceId
        AND status = ANY(@blocking)
        AND end_date >= CURRENT_DATE
      LIMIT 1
      '''),
      parameters: {'spaceId': spaceId, 'blocking': occupyingStatusList},
    );
    return res.isNotEmpty;
  }

  /// Slots held by occupying bookings overlapping the window, plus a flag for
  /// legacy (slot-less) bookings that hold the whole property.
  Future<({Set<String> ids, bool legacy})> _occupiedSpaceIds(
    String parkingId,
    DateTime start,
    DateTime end, {
    dynamic conn,
  }) async {
    Future<Result> run(dynamic c) => c.execute(
      Sql.named('''
      SELECT parking_space_id FROM bookings
      WHERE parking_id = @parkingId
        AND status = ANY(@blocking)
        AND start_date <= @endDate
        AND end_date >= @startDate
      '''),
      parameters: {
        'parkingId': parkingId,
        'blocking': occupyingStatusList,
        'startDate': start,
        'endDate': end,
      },
    );

    final res = conn != null
        ? await run(conn)
        : await Db.pool.withConnection(run);
    final ids = <String>{};
    var legacy = false;
    for (final r in res) {
      final raw = r.toColumnMap()['parking_space_id']?.toString();
      if (raw == null || raw.isEmpty) {
        legacy = true;
      } else {
        ids.add(raw);
      }
    }
    return (ids: ids, legacy: legacy);
  }

  Future<Map<String, dynamic>?> _parkingRow(String id, {dynamic conn}) async {
    if (!isUuid(id)) return null;
    Future<Result> run(dynamic c) => c.execute(
      Sql.named('SELECT * FROM parking_listings WHERE id = @id'),
      parameters: {'id': id},
    );
    final res = conn != null
        ? await run(conn)
        : await Db.pool.withConnection(run);
    if (res.isEmpty) return null;
    return res.first.toColumnMap();
  }

  static double? _num(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// True when [id] is a well-formed UUID (all `id` columns use `uuid`).
  static bool isUuid(String id) => _uuidPattern.hasMatch(id);
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
