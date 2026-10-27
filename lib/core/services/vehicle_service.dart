import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/vehicle.dart';

/// Saved-vehicle API for the Vehicle User.
class VehicleService {
  final ApiClient _client;

  VehicleService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Vehicle> create({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final data = await _client.post(
      ApiConstants.vehicles,
      body: payload,
      token: token,
    ) as Map<String, dynamic>;
    return Vehicle.fromJson(data);
  }

  Future<List<Vehicle>> listMy(String token) async {
    final data = await _client.get(
      ApiConstants.vehicles,
      token: token,
    ) as Map<String, dynamic>;
    final raw = data['vehicles'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(Vehicle.fromJson).toList();
  }

  Future<Vehicle> getById(String id, {required String token}) async {
    final data = await _client.get(
      ApiConstants.vehicleById(id),
      token: token,
    ) as Map<String, dynamic>;
    return Vehicle.fromJson(data);
  }

  Future<Vehicle> update({
    required String id,
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final data = await _client.put(
      ApiConstants.vehicleById(id),
      body: payload,
      token: token,
    ) as Map<String, dynamic>;
    return Vehicle.fromJson(data);
  }

  Future<void> delete(String id, {required String token}) async {
    await _client.delete(ApiConstants.vehicleById(id), token: token);
  }
}
