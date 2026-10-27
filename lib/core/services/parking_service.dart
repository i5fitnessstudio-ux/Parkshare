import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/parking.dart';
import '../../shared/models/parking_space.dart';

/// Parking listing API (create/read/update/delete/nearby/owner).
class ParkingService {
  final ApiClient _client;

  ParkingService({ApiClient? client}) : _client = client ?? ApiClient();

  /// Publishes a parking listing (owner). [payload] uses the API camelCase
  /// keys (see parking draft -> toPayload()).
  Future<ParkingListing> create({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final data = await _client.post(
      ApiConstants.parkings,
      body: payload,
      token: token,
    ) as Map<String, dynamic>;
    return ParkingListing.fromJson(data);
  }

  /// Detail read. Passing [vehicleId] (+ a date window) makes the server add the
  /// slot-level `availability` block the user screens render.
  Future<ParkingListing> getById(
    String id, {
    required String token,
    String? vehicleId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final data = await _client.get(
      ApiConstants.parkingById(
        id,
        vehicleId: vehicleId,
        startDate: startDate,
        endDate: endDate,
      ),
      token: token,
    ) as Map<String, dynamic>;
    return ParkingListing.fromJson(data);
  }

  /// The individual physical slots of a listing, each flagged available / not
  /// for the requested window.
  Future<ParkingSpacesResult> getSpaces(
    String parkingId, {
    required String token,
    String? vehicleId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final data = await _client.get(
      ApiConstants.parkingSpaces(
        parkingId,
        vehicleId: vehicleId,
        startDate: startDate,
        endDate: endDate,
      ),
      token: token,
    ) as Map<String, dynamic>;
    return ParkingSpacesResult.fromJson(data);
  }

  Future<List<ParkingListing>> listByOwner(
    String ownerId, {
    required String token,
  }) async {
    final data = await _client.get(
      ApiConstants.ownerParkings(ownerId),
      token: token,
    ) as Map<String, dynamic>;
    return _parseList(data);
  }

  /// Nearby search — Haversine is computed server-side; results come sorted
  /// by distanceKm ascending.
  ///
  /// With a [vehicleId] the server attaches per-parking slot availability, so
  /// the map can grey out parkings whose matching slots are all taken.
  Future<List<ParkingListing>> nearby({
    required double lat,
    required double lng,
    required String token,
    double radiusKm = 5,
    String? vehicleId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final data = await _client.get(
      ApiConstants.nearbyParkings(
        lat: lat,
        lng: lng,
        radiusKm: radiusKm,
        vehicleId: vehicleId,
        startDate: startDate,
        endDate: endDate,
      ),
      token: token,
    ) as Map<String, dynamic>;
    return _parseList(data);
  }

  Future<ParkingListing> update({
    required String id,
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final data = await _client.put(
      ApiConstants.parkingById(id),
      body: payload,
      token: token,
    ) as Map<String, dynamic>;
    return ParkingListing.fromJson(data);
  }

  Future<void> delete(String id, {required String token}) async {
    await _client.delete(ApiConstants.parkingById(id), token: token);
  }

  /// Read-only slot availability probe for a date window. UX only — the
  /// authoritative guard against double booking still runs inside
  /// POST /api/bookings.
  ///
  /// [vehicleId] makes the server use the saved vehicle's type AND its real
  /// dimensions, so the answer is "a free slot this vehicle actually fits in".
  /// [vehicleType] alone gives type-level counts without a fit check.
  Future<ParkingAvailability> checkAvailability({
    required String parkingId,
    required DateTime startDate,
    required DateTime endDate,
    required String token,
    String? vehicleId,
    String? vehicleType,
  }) async {
    final data = await _client.get(
      ApiConstants.parkingAvailability(
        id: parkingId,
        startDate: _isoDate(startDate),
        endDate: _isoDate(endDate),
        vehicleId: vehicleId,
        vehicleType: vehicleType,
      ),
      token: token,
    ) as Map<String, dynamic>;
    return ParkingAvailability.fromJson(data);
  }

  /// `YYYY-MM-DD` — the format the API expects for date windows.
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  List<ParkingListing> _parseList(Map<String, dynamic> data) {
    final raw = data['parkings'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ParkingListing.fromJson)
        .toList();
  }
}

/// Slots + availability of one parking, from `GET /parkings/{id}/spaces`.
class ParkingSpacesResult {
  final String parkingId;
  final List<ParkingSpace> spaces;
  final ParkingAvailability? availability;

  const ParkingSpacesResult({
    required this.parkingId,
    this.spaces = const [],
    this.availability,
  });

  List<ParkingSpace> get carSpaces =>
      spaces.where((s) => s.isCar).toList(growable: false);
  List<ParkingSpace> get bikeSpaces =>
      spaces.where((s) => s.isBike).toList(growable: false);

  factory ParkingSpacesResult.fromJson(Map<String, dynamic> json) =>
      ParkingSpacesResult(
        parkingId: json['parkingId']?.toString() ?? '',
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
      );
}

/// Unauthorised/not-found passthrough so callers can special-case 404.
class ParkingNotFound implements Exception {}
