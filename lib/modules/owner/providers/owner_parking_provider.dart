import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/parking_service.dart';
import '../../../core/services/photo_picker_service.dart';
import '../../../shared/models/parking.dart';

/// Owner parking state: my listings + photo upload + publish/delete.
class OwnerParkingProvider extends ChangeNotifier {
  final ParkingService _service;
  final ApiClient _client;

  List<ParkingListing> _parkings = [];
  bool _loading = false;
  String? _error;
  int _sessionEpoch = 0;

  OwnerParkingProvider({ParkingService? service, ApiClient? client})
    : _service = service ?? ParkingService(),
      _client = client ?? ApiClient();

  List<ParkingListing> get parkings => List.unmodifiable(_parkings);
  bool get loading => _loading;
  String? get error => _error;

  ParkingListing? byId(String id) {
    for (final p in _parkings) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> loadMyParkings({
    required String token,
    required String ownerId,
  }) async {
    final epoch = _sessionEpoch;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final rows = await _service.listByOwner(ownerId, token: token);
      if (epoch != _sessionEpoch) return;
      _parkings = rows;
    } catch (e) {
      if (epoch == _sessionEpoch) _error = e.toString();
    } finally {
      if (epoch == _sessionEpoch) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Clears owner-scoped listings when the signed-in identity changes.
  void resetForAccountSwitch() {
    _sessionEpoch++;
    _parkings = const [];
    _loading = false;
    _error = null;
    notifyListeners();
  }

  /// Uploads photos and returns their public URLs (used by the owner's
  /// publish flow). Never stores local device paths.
  Future<List<String>> uploadPhotos({
    required String token,
    required List<PickedPhoto> photos,
  }) async {
    final urls = <String>[];
    for (final photo in photos) {
      final result = await _client.uploadPhoto(
        bytes: photo.bytes,
        filename: photo.filename,
        contentType: photo.contentType,
        token: token,
      );
      urls.add(result['url'] as String);
    }
    return urls;
  }

  /// Publishes the draft; on success refreshes the list so the dashboard is
  /// real data (no fake entries).
  Future<ParkingListing> publish({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final created = await _service.create(token: token, payload: payload);
    // Refresh from the server so current/derived fields are accurate.
    await loadMyParkings(token: token, ownerId: created.ownerId);
    return created;
  }

  /// Updates an existing listing (Edit Parking reuses the same wizard) and
  /// refreshes the list so capacity/utilisation stay server-derived.
  Future<ParkingListing> update({
    required String token,
    required String parkingId,
    required Map<String, dynamic> payload,
  }) async {
    final updated = await _service.update(
      id: parkingId,
      token: token,
      payload: payload,
    );
    await loadMyParkings(token: token, ownerId: updated.ownerId);
    return updated;
  }

  Future<void> remove(String id, {required String token}) async {
    await _service.delete(id, token: token);
    _parkings = _parkings.where((p) => p.id != id).toList();
    notifyListeners();
  }
}
