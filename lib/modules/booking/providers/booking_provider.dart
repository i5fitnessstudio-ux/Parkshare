import 'package:flutter/foundation.dart';

import '../../../core/services/booking_service.dart';
import '../../../shared/models/booking.dart';

/// Booking state for both roles. Which list is populated depends on the
/// active user's role: owner -> listByOwner, vehicle user -> listByUser.
class BookingProvider extends ChangeNotifier {
  final BookingService _service;

  List<Booking> _bookings = [];
  bool _loading = false;
  String? _error;
  String? _loadedForUserId;
  String? _loadedForOwnerId;
  int _sessionEpoch = 0;

  BookingProvider({BookingService? service})
    : _service = service ?? BookingService();

  List<Booking> get bookings => List.unmodifiable(_bookings);
  bool get loading => _loading;
  String? get error => _error;

  Booking? byId(String id) {
    for (final b in _bookings) {
      if (b.bookingId == id) return b;
    }
    return null;
  }

  /// Loads the caller-role booking list. Passing an ownerId loads owner
  /// bookings; userId loads user bookings.
  Future<void> load({
    required String token,
    String? ownerId,
    String? userId,
  }) async {
    final epoch = _sessionEpoch;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (ownerId != null) {
        final rows = await _service.listByOwner(ownerId, token: token);
        if (epoch != _sessionEpoch) return;
        _bookings = rows;
        _loadedForOwnerId = ownerId;
        _loadedForUserId = null;
      } else if (userId != null) {
        final rows = await _service.listByUser(userId, token: token);
        if (epoch != _sessionEpoch) return;
        _bookings = rows;
        _loadedForUserId = userId;
        _loadedForOwnerId = null;
      }
    } catch (e) {
      if (epoch == _sessionEpoch) _error = e.toString();
    } finally {
      if (epoch == _sessionEpoch) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Clears every booking cached for the previous signed-in identity.
  void resetForAccountSwitch() {
    _sessionEpoch++;
    _bookings = const [];
    _loading = false;
    _error = null;
    _loadedForUserId = null;
    _loadedForOwnerId = null;
    notifyListeners();
  }

  Future<Booking> create({
    required String token,
    required String parkingId,
    required String vehicleId,
    required String rentalType,
    required String startDate,
    required String endDate,
  }) async {
    final b = await _service.create(
      token: token,
      parkingId: parkingId,
      vehicleId: vehicleId,
      rentalType: rentalType,
      startDate: startDate,
      endDate: endDate,
    );
    await load(
      token: token,
      userId: _loadedForUserId,
      ownerId: _loadedForOwnerId,
    );
    return b;
  }

  Future<Booking> accept(String id, {required String token}) async {
    final b = await _service.accept(id, token: token);
    await _reload(token);
    return b;
  }

  Future<Booking> reject(String id, {required String token}) async {
    final b = await _service.reject(id, token: token);
    await _reload(token);
    return b;
  }

  Future<void> _reload(String token) =>
      load(token: token, userId: _loadedForUserId, ownerId: _loadedForOwnerId);
}
