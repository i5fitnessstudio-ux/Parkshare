import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/booking.dart';

/// Booking API (create, lists, detail, accept/reject).
class BookingService {
  final ApiClient _client;

  BookingService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Booking> create({
    required String token,
    required String parkingId,
    required String vehicleId,
    required String rentalType,
    required String startDate,
    required String endDate,
  }) async {
    final data = await _client.post(
      ApiConstants.bookings,
      body: {
        'parkingId': parkingId,
        'vehicleId': vehicleId,
        'rentalType': rentalType,
        'startDate': startDate,
        'endDate': endDate,
      },
      token: token,
    ) as Map<String, dynamic>;
    return Booking.fromJson(data);
  }

  Future<List<Booking>> listByOwner(
    String ownerId, {
    required String token,
  }) async {
    final data = await _client.get(
      ApiConstants.ownerBookings(ownerId),
      token: token,
    ) as Map<String, dynamic>;
    return _parseList(data);
  }

  Future<List<Booking>> listByUser(
    String userId, {
    required String token,
  }) async {
    final data = await _client.get(
      ApiConstants.userBookings(userId),
      token: token,
    ) as Map<String, dynamic>;
    return _parseList(data);
  }

  Future<Booking> getById(String id, {required String token}) async {
    final data = await _client.get(
      ApiConstants.bookingById(id),
      token: token,
    ) as Map<String, dynamic>;
    return Booking.fromJson(data);
  }

  Future<Booking> accept(String id, {required String token}) async {
    final data = await _client.put(
      ApiConstants.acceptBooking(id),
      body: const {},
      token: token,
    ) as Map<String, dynamic>;
    return Booking.fromJson(data);
  }

  Future<Booking> reject(String id, {required String token}) async {
    final data = await _client.put(
      ApiConstants.rejectBooking(id),
      body: const {},
      token: token,
    ) as Map<String, dynamic>;
    return Booking.fromJson(data);
  }

  List<Booking> _parseList(Map<String, dynamic> data) {
    final raw = data['bookings'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(Booking.fromJson).toList();
  }
}
