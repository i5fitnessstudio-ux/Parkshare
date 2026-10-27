import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/services/location_search_service.dart';
import '../../../core/services/parking_service.dart';
import '../../../shared/models/parking.dart';

/// Explicit load phases so the UI can never show an empty state before the
/// request has actually finished.
enum NearbyPhase { idle, loading, success, empty, error }

/// Vehicle-user map state: current viewport center, search, parking markers,
/// selected preview + nearby fetch.
class UserMapProvider extends ChangeNotifier {
  final ParkingService _parkingService;

  List<ParkingListing> _nearby = [];
  bool _loading = false;
  bool _fetching = false; // debounced search-in-flight
  String? _error;
  NearbyPhase _phase = NearbyPhase.idle;
  String? _searchQuery;
  bool _usingGps = true; // false once the user searched a location
  ParkingListing? _selected;

  // Camera center (lat/lng doubles to keep latlong2 out of providers).
  double? _centerLat;
  double? _centerLng;

  // Vehicle the map filters slot availability against (set by the map tab).
  String? _activeVehicleId;
  String? _activeVehicleType;

  Timer? _debounce;

  UserMapProvider({ParkingService? parkingService})
    : _parkingService = parkingService ?? ParkingService();

  List<ParkingListing> get nearby => List.unmodifiable(_nearby);
  bool get loading => _loading;
  bool get fetching => _fetching;
  NearbyPhase get phase => _phase;
  bool get busy => _loading || _fetching;
  String? get error => _error;
  String? get searchQuery => _searchQuery;
  bool get usingGps => _usingGps;
  ParkingListing? get selected => _selected;
  double? get centerLat => _centerLat;
  double? get centerLng => _centerLng;

  /// The vehicle nearby results are filtered against. Its saved dimensions are
  /// sent to the server so a parking is only reported as available when a slot
  /// this vehicle physically fits in is actually free.
  String? get activeVehicleId => _activeVehicleId;
  String? get activeVehicleType => _activeVehicleType;

  /// Parkings in the viewport that still have a free slot for the active
  /// vehicle. A parking is only excluded when the server says so — never on a
  /// client-side guess.
  List<ParkingListing> get bookableNearby {
    if (_activeVehicleType == null) return nearby;
    return _nearby
        .where((p) => p.availability?.isAvailable ?? true)
        .toList(growable: false);
  }

  /// Points the map at a vehicle (or clears it with null) and re-queries the
  /// current viewport so the availability matches what the user actually drives.
  ///
  /// [force] re-queries even when the vehicle id and type are unchanged. That
  /// matters after "Save & Find Parking": the vehicle may only have new
  /// dimensions, and the server evaluates slot availability from those real
  /// dimensions, so the markers have to be recomputed.
  Future<void> setActiveVehicle(
    String? vehicleId,
    String? vehicleType, {
    bool force = false,
  }) async {
    if (!force &&
        _activeVehicleId == vehicleId &&
        _activeVehicleType == vehicleType) {
      return;
    }
    _activeVehicleId = vehicleId;
    _activeVehicleType = vehicleType;
    _selected = null;
    notifyListeners();
    if (_centerLat == null || _centerLng == null) return;
    await _fetchNearby();
  }

  /// True only when the request finished and really returned nothing.
  bool get isEmpty => !busy && _phase == NearbyPhase.empty && _error == null;

  void select(ParkingListing? p) {
    _selected = p;
    notifyListeners();
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  /// Called whenever the map camera stops moving (~600 ms debounce).
  /// Fetches nearby parkings for the new center, keeping the GPS-vs-search
  /// override semantics: searching a place takes over until the user taps
  /// "Current Location".
  void onCameraSettled({required double lat, required double lng}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (_usingGps) {
        _centerLat = lat;
        _centerLng = lng;
      }
      _fetchNearby();
    });
  }

  Future<void> _fetchNearby() async {
    final lat = _centerLat;
    final lng = _centerLng;
    if (lat == null || lng == null) return;
    _fetching = true;
    _error = null;
    _phase = NearbyPhase.loading;
    notifyListeners();
    try {
      final token = _readToken();
      final list = await _parkingService.nearby(
        lat: lat,
        lng: lng,
        token: token,
        vehicleId: _activeVehicleId,
      );
      _nearby = list;
      _phase = list.isEmpty ? NearbyPhase.empty : NearbyPhase.success;
    } catch (e) {
      ErrorMessages.logTechnical('nearby', e);
      _error = ErrorMessages.nearbyFailed;
      _phase = NearbyPhase.error;
    } finally {
      _fetching = false;
      notifyListeners();
    }
  }

  /// Loads real green markers around the provided center.
  Future<void> loadNearby({
    required double lat,
    required double lng,
    required double radiusKm,
  }) async {
    _loading = true;
    _error = null;
    _phase = NearbyPhase.loading;
    _centerLat = lat;
    _centerLng = lng;
    notifyListeners();
    try {
      final token = _readToken();
      final list = await _parkingService.nearby(
        lat: lat,
        lng: lng,
        token: token,
        radiusKm: radiusKm,
        vehicleId: _activeVehicleId,
      );
      _nearby = list;
      _phase = list.isEmpty ? NearbyPhase.empty : NearbyPhase.success;
    } catch (e) {
      ErrorMessages.logTechnical('loadNearby', e);
      _error = ErrorMessages.nearbyFailed;
      _phase = NearbyPhase.error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// A search result overrides GPS: markers retarget to the searched spot.
  Future<void> searchAndCenter(PlaceSearchResult place) async {
    _searchQuery = place.name;
    _usingGps = false;
    _centerLat = place.latitude;
    _centerLng = place.longitude;
    _selected = null;
    await _fetchNearby();
  }

  /// Back to GPS: re-enables following the current location.
  Future<void> backToGps() async {
    _usingGps = true;
    _searchQuery = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    if (_phase == NearbyPhase.error) {
      _phase = _nearby.isEmpty ? NearbyPhase.empty : NearbyPhase.success;
    }
    notifyListeners();
  }

  /// Re-runs the nearby fetch around the current center (Retry button).
  Future<void> retry() async {
    if (_centerLat == null || _centerLng == null) return;
    await loadNearby(lat: _centerLat!, lng: _centerLng!, radiusKm: 5);
  }

  // The current session token. Set by the map screen from AuthProvider so
  // the debounced internal fetches can authenticate without threading the
  // token through every call.
  String? token;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String _readToken() => token ?? '';
}
