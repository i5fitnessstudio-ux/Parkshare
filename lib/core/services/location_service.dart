import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Result of a location permission check / fetch.
enum LocationAccess { granted, denied, disabled, unavailable }

/// A resolved coordinate plus where it came from (used for map attribution).
enum LocationSource { none, gps, lastKnown }

class LocationPoint {
  final double latitude;
  final double longitude;
  final double? accuracyM;

  const LocationPoint(this.latitude, this.longitude, {this.accuracyM});

  /// Rejects garbage fixes so the map can never centre on an impossible
  /// coordinate (null island, out-of-range or non-finite values).
  bool get isValid {
    if (latitude.isNaN || longitude.isNaN) return false;
    if (latitude.isInfinite || longitude.isInfinite) return false;
    if (latitude < -90 || latitude > 90) return false;
    if (longitude < -180 || longitude > 180) return false;
    if (latitude == 0 && longitude == 0) return false; // null island
    return true;
  }

  @override
  String toString() =>
      'LocationPoint($latitude, $longitude, accuracy: $accuracyM)';
}

/// Geolocation wrapper. Never crashes: every public method returns a status
/// instead of throwing.
class LocationService {
  /// Deterministic E2E build (`--dart-define=E2E_TEST=true`): no native
  /// permission dialog and no real GPS — the geo-fixed emulator coordinates
  /// are returned directly (mirrors `adb emu geo fix 72.8777 19.0760`).
  //
  // NOTE: must be `const` — bool.fromEnvironment only resolves the define in
  // a const context; a non-const `static final` returns false at runtime and
  // silently fell back to the real geolocator (which can hang in tests).
  static const bool _e2e = bool.fromEnvironment('E2E_TEST');

  /// Fixed point used by the deterministic E2E build (Mumbai, matches the
  /// emulator geo fix used by the integration test).
  static const LocationPoint e2ePoint = LocationPoint(19.0760, 72.8777);

  static const double _goodAccuracyM = 200;

  /// Hard ceiling on a single GPS read. Without this, `getCurrentPosition`
  /// can block for a very long time on an emulator/device with no fix, which
  /// left the map showing whatever it had before.
  static const Duration gpsTimeout = Duration(seconds: 12);

  /// In-memory cache of the last VALID fix (the "last known location" tier,
  /// used when a fresh read times out so GPS is not hammered).
  static LocationPoint? _lastValid;

  static LocationPoint? get lastValid => _lastValid;

  /// Checks permission state without prompting.
  Future<LocationAccess> check() async {
    if (_e2e) return LocationAccess.granted;
    try {
      return _mapPermission(await Geolocator.checkPermission());
    } catch (_) {
      return LocationAccess.unavailable;
    }
  }

  /// True when the user chose "don't ask again" — the only case where we
  /// should send the user to the OS settings page instead of re-prompting.
  Future<bool> isPermanentlyDenied() async {
    if (_e2e) return false;
    try {
      return await Geolocator.checkPermission() ==
          LocationPermission.deniedForever;
    } catch (_) {
      return false;
    }
  }

  /// Requests permission (if needed) then returns the current access state.
  /// Geolocator only shows the OS dialog while the permission is still
  /// `denied` (not `deniedForever`), so this never spams dialogs.
  Future<LocationAccess> request() async {
    if (_e2e) return LocationAccess.granted;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return LocationAccess.disabled;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return _mapPermission(permission);
    } catch (_) {
      return LocationAccess.unavailable;
    }
  }

  /// Real GPS fix, bounded by [gpsTimeout]. Returns null (never throws) when
  /// permission/services are missing or the read times out.
  Future<LocationPoint?> currentPosition({
    Duration timeout = gpsTimeout,
  }) async {
    if (_e2e) return e2ePoint;
    final access = await request();
    if (access != LocationAccess.granted) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).timeout(timeout);
      final point = LocationPoint(
        position.latitude,
        position.longitude,
        accuracyM: position.accuracy,
      );
      if (!point.isValid) {
        debugPrint('[LocationService] implausible fix ignored: $point');
        return await lastKnownPosition();
      }
      _lastValid = point;
      return point;
    } catch (e) {
      debugPrint('[LocationService] getCurrentPosition failed: $e');
      // Tier 2 of the priority chain: the platform's last known fix.
      return lastKnownPosition();
    }
  }

  /// Tier 2 — the platform's cached fix (fast, permission already granted).
  /// Never prompts and never throws.
  Future<LocationPoint?> lastKnownPosition() async {
    if (_e2e) return e2ePoint;
    if (await check() != LocationAccess.granted) return _lastValid;
    try {
      final position = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 3),
      );
      if (position == null) return _lastValid;
      final point = LocationPoint(
        position.latitude,
        position.longitude,
        accuracyM: position.accuracy,
      );
      if (!point.isValid) return _lastValid;
      _lastValid = point;
      return point;
    } catch (e) {
      debugPrint('[LocationService] getLastKnownPosition failed: $e');
      return _lastValid;
    }
  }

  /// True when the emulator/app has a location accurate enough to show
  /// meaningful "nearby" results (emulators report ~0 m via `geo fix`).
  bool isAccurate(LocationPoint point) =>
      point.accuracyM == null || point.accuracyM! <= _goodAccuracyM;

  /// Sends the user to the OS app settings (used when permission was denied
  /// permanently — we must not re-prompt).
  Future<bool> openAppSettings() async {
    if (_e2e) return true;
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  /// Sends the user to the OS location-services settings (used when the
  /// device location toggle is off).
  Future<bool> openLocationSettings() async {
    if (_e2e) return true;
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }

  LocationAccess _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationAccess.granted;
      case LocationPermission.denied:
      case LocationPermission.deniedForever:
        return LocationAccess.denied;
      default:
        return LocationAccess.unavailable;
    }
  }
}
