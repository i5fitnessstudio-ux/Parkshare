import 'package:flutter/foundation.dart';

import '../../../core/services/vehicle_service.dart';
import '../../../shared/models/vehicle.dart';

/// Vehicle User's saved vehicles.
class VehicleProvider extends ChangeNotifier {
  final VehicleService _service;

  List<Vehicle> _vehicles = [];
  bool _loading = false;
  String? _error;
  Vehicle? _primary;

  VehicleProvider({VehicleService? service})
    : _service = service ?? VehicleService();

  List<Vehicle> get vehicles => List.unmodifiable(_vehicles);
  bool get loading => _loading;
  String? get error => _error;
  Vehicle? get primary => _primary;

  Vehicle? byId(String id) {
    for (final v in _vehicles) {
      if (v.id == id) return v;
    }
    return null;
  }

  Future<void> loadMyVehicles({required String token}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _vehicles = await _service.listMy(token);
      _recomputePrimary();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Vehicle> create({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final created = await _service.create(token: token, payload: payload);
    await loadMyVehicles(token: token);
    return created;
  }

  Future<Vehicle> update({
    required String id,
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final updated = await _service.update(
      id: id,
      token: token,
      payload: payload,
    );
    await loadMyVehicles(token: token);
    return updated;
  }

  Future<void> delete(String id, {required String token}) async {
    await _service.delete(id, token: token);
    await loadMyVehicles(token: token);
  }

  void _recomputePrimary() {
    _primary = null;
    for (final v in _vehicles) {
      if (v.isPrimary) {
        _primary = v;
        break;
      }
    }
    _primary ??= _vehicles.isNotEmpty ? _vehicles.first : null;
  }
}
