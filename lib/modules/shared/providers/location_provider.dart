import 'package:flutter/foundation.dart';

import '../../../core/network/error_messages.dart';
import '../../../core/services/location_service.dart';

/// Shared current-location state (GPS). Map screens consume this; the
/// vehicle-user map provider combines it with the parking search markers.
///
/// Resolution priority (never re-hammers GPS, never re-prompts):
///   1. real current GPS fix
///   2. last known valid location (service cache / in-memory cache)
///   3. Tamil Nadu (Chennai) fallback — applied by the map, not here
class LocationProvider extends ChangeNotifier {
  final LocationService _service = LocationService();

  LocationAccess _access = LocationAccess.unavailable;
  LocationPoint? _point;
  LocationSource _source = LocationSource.none;
  bool _loading = false;
  bool _failed = false;
  String? _error;
  bool _permissionPermanentlyDenied = false;

  LocationAccess get access => _access;
  LocationPoint? get point => _point;
  LocationSource get source => _source;
  bool get loading => _loading;

  /// True once a read completed without a usable fix — the map uses this to
  /// tell "Getting location…" apart from a real error banner.
  bool get failed => _failed;
  String? get errorMessage => _error;
  bool get hasFix => _point != null;
  bool get permissionPermanentlyDenied => _permissionPermanentlyDenied;
  double? get latitude => _point?.latitude;
  double? get longitude => _point?.longitude;

  /// Prompts for permission (if needed) and fetches the current position.
  ///
  /// Safe to call from several screens: a cached fix short-circuits unless
  /// [force] is set (the "current location" button), so the OS dialog and the
  /// GPS radio are touched at most once per user action.
  /// Never throws — failures surface as [errorMessage] + [access].
  Future<void> refresh({bool force = false}) async {
    if (_loading) return;
    if (!force && _point != null) return; // already have a usable fix

    _loading = true;
    _failed = false;
    _error = null;
    notifyListeners();

    _access = await _service.request();
    if (_access == LocationAccess.granted) {
      _permissionPermanentlyDenied = false;
      final fresh = await _service.currentPosition();
      if (fresh != null) {
        _point = fresh;
        _source = LocationSource.gps;
      } else {
        // Tier 2: last known (platform cache / in-memory cache).
        final cached = await _service.lastKnownPosition();
        if (cached != null) {
          _point = cached;
          _source = LocationSource.lastKnown;
        } else {
          _failed = true;
          _error = ErrorMessages.locationUnavailable;
        }
      }
    } else {
      _permissionPermanentlyDenied = await _service.isPermanentlyDenied();
      _failed = true;
      _error = switch (_access) {
        LocationAccess.denied => ErrorMessages.locationPermission,
        LocationAccess.disabled => ErrorMessages.locationServicesOff,
        _ => ErrorMessages.locationUnavailable,
      };
    }

    _loading = false;
    notifyListeners();
  }

  /// Silent warm-up used at login so the Map tab can render immediately:
  /// no OS dialog when the permission was already answered, no GPS read when
  /// a fix is already cached.
  Future<void> preload() async {
    if (_loading || _point != null) return;
    final access = await _service.check();
    _access = access;
    if (access != LocationAccess.granted) {
      _permissionPermanentlyDenied = await _service.isPermanentlyDenied();
      notifyListeners();
      return;
    }
    final cached = await _service.lastKnownPosition();
    if (cached != null) {
      _point = cached;
      _source = LocationSource.lastKnown;
      notifyListeners();
    }
  }

  /// Purely checks permission without prompting (keeps the map non-crashy
  /// on first frame).
  Future<void> checkOnly() async {
    _access = await _service.check();
    notifyListeners();
  }

  Future<bool> openAppSettings() => _service.openAppSettings();

  Future<bool> openLocationSettings() => _service.openLocationSettings();
}
