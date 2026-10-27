import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/services/booking_service.dart';
import '../../../core/services/parking_service.dart';
import '../../../core/services/payment_service.dart';
import '../../../shared/models/booking.dart';
import '../../../shared/models/owner_payment_info.dart';
import '../../../shared/models/parking.dart';

/// Owner dashboard aggregate stats, computed from the real backend list
/// endpoints (parkings + owner bookings). No fake data.
class OwnerDashboardProvider extends ChangeNotifier {
  final ParkingService _parkingService;
  final BookingService _bookingService;
  final PaymentService _paymentService;

  List<ParkingListing> _parkings = [];
  List<Booking> _bookings = [];

  bool _loading = false;
  bool _confirmingCod = false;
  String? _error;
  OwnerEarningsSummary? _earnings;
  int _sessionEpoch = 0;

  bool _isCurrent(int epoch) => epoch == _sessionEpoch;

  OwnerDashboardProvider({
    ParkingService? parkingService,
    BookingService? bookingService,
    PaymentService? paymentService,
  }) : _parkingService = parkingService ?? ParkingService(),
       _bookingService = bookingService ?? BookingService(),
       _paymentService = paymentService ?? PaymentService();

  List<ParkingListing> get parkings => List.unmodifiable(_parkings);
  List<Booking> get bookings => List.unmodifiable(_bookings);
  bool get loading => _loading;
  String? get error => _error;

  /// True while a "Mark COD Received" request is in flight.
  bool get confirmingCod => _confirmingCod;

  /// The server-computed settlement totals, when they could be loaded.
  OwnerEarningsSummary? get earningsSummary => _earnings;

  // ---- Stats ----
  int get totalParkings => _parkings.length;
  int get availableParkings =>
      _parkings.where((p) => p.available && p.currentBooking == null).length;
  int get occupiedParkings =>
      _parkings.where((p) => p.currentBooking != null).length;

  int get pendingRequests =>
      _bookings.where((b) => b.status == BookingStatus.requested).length;

  int get activeBookings => _bookings
      .where(
        (b) =>
            b.status == BookingStatus.confirmed ||
            b.status == BookingStatus.active ||
            b.status == BookingStatus.paymentPending ||
            b.status == BookingStatus.accepted,
      )
      .length;

  int get completedBookings =>
      _bookings.where((b) => b.status == BookingStatus.completed).length;

  /// Bookings where the user chose Cash on Delivery but has not handed the
  /// cash over yet. These are NOT earnings and do NOT hold the slot.
  int get codPendingCount =>
      _bookings.where((b) => b.status == BookingStatus.codPending).length;

  /// UPI payments the customer declared but the owner has not verified yet.
  ///
  /// AUDIT C-01: these are also NOT earnings. Surfaced separately so the owner
  /// can see there is money to check, without it ever being counted as money in
  /// hand.
  int get upiAwaitingVerificationCount =>
      _bookings.where((b) => b.isLegacyDirectUpi).length;

  /// Total Earnings.
  ///
  /// AUDIT C-02: this is now the **server's** figure
  /// (`GET /api/payments/owner/earnings`), aggregated in SQL over every booking
  /// the owner owns. The local derivation in [_localEarnings] is only used as a
  /// fallback when that call fails, and [earningsIsAuthoritative] reports which
  /// one is on screen.
  ///
  /// Money counts only for `SUCCESS` and `COD_CONFIRMED`. `UPI_PENDING_VERIFICATION`,
  /// `PENDING`, `COD_PENDING`, `FAILED` and `REFUNDED` are all excluded.
  double get totalEarnings => _earnings?.totalEarnings ?? _localEarnings ?? 0;

  /// False when the dashboard is showing a locally derived figure because the
  /// server aggregate could not be fetched. Surfaced so the UI can say so
  /// rather than presenting a client-computed number as authoritative.
  bool get earningsIsAuthoritative => _earnings != null;

  /// Client-side sum over the locally cached bookings. Fallback only.
  ///
  /// Retained so the dashboard still renders numbers during an outage, but it
  /// is only correct for the bookings that happen to be in memory, which is
  /// exactly why it is no longer the primary source.
  double? get _localEarnings {
    var sum = 0.0;
    for (final b in _bookings) {
      if (PaymentStatus.paid.contains(b.paymentStatus)) {
        sum += b.amount;
      }
    }
    return sum;
  }

  /// Number of bookings that contributed to [totalEarnings].
  int get paidBookingsCount =>
      _earnings?.paidBookings ??
      _bookings
          .where((b) => PaymentStatus.paid.contains(b.paymentStatus))
          .length;

  Future<void> load({required String token, required String ownerId}) async {
    final epoch = _sessionEpoch;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _parkingService.listByOwner(ownerId, token: token),
        _bookingService.listByOwner(ownerId, token: token),
      ]);
      if (!_isCurrent(epoch)) return;
      _parkings = results[0] as List<ParkingListing>;
      _bookings = results[1] as List<Booking>;
      // Audit C-02: the money figure comes from the server, not from a local
      // sum. A failure here is deliberately non-fatal — the local fallback keeps
      // the dashboard usable and [earningsIsAuthoritative] reports the downgrade.
      final earnings = await _loadEarnings(token);
      if (!_isCurrent(epoch)) return;
      _earnings = earnings;
    } catch (e) {
      if (_isCurrent(epoch)) _error = e.toString();
    } finally {
      if (_isCurrent(epoch)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Server aggregate, or null when unavailable.
  Future<OwnerEarningsSummary?> _loadEarnings(String token) async {
    try {
      return await _paymentService.fetchOwnerEarnings(token: token);
    } catch (e) {
      ErrorMessages.logTechnical('ownerEarnings', e);
      return null;
    }
  }

  /// Owner taps "Mark COD Received".
  ///
  /// This is the single gate for the COD flow: the slot is allocated, the
  /// booking becomes CONFIRMED, the payment becomes COD_CONFIRMED and the
  /// amount immediately enters [totalEarnings]. The refreshed booking is
  /// patched into the cached list so every badge and stat on screen flips at
  /// once.
  Future<bool> confirmCod({
    required String token,
    required String bookingId,
  }) async {
    if (_confirmingCod) return false;
    final epoch = _sessionEpoch;
    _confirmingCod = true;
    _error = null;
    notifyListeners();
    try {
      final updated = await _paymentService.confirmCod(
        token: token,
        bookingId: bookingId,
      );
      if (!_isCurrent(epoch)) return false;
      final index = _bookings.indexWhere(
        (b) => b.bookingId == updated.bookingId,
      );
      if (index >= 0) {
        final next = [..._bookings];
        next[index] = updated;
        _bookings = next;
      }
      // Availability and the stats are derived from the bookings list, but
      // the listings carry their own `currentBooking`, so refresh both to be
      // sure the slot shows as occupied everywhere.
      await load(token: token, ownerId: updated.ownerId);
      return _isCurrent(epoch);
    } on ApiException catch (e) {
      ErrorMessages.logTechnical('confirmCod', e);
      if (!_isCurrent(epoch)) return false;
      _error = ErrorMessages.forUi(
        e,
        fallback: 'Could not confirm the cash payment. Please try again.',
      );
      return false;
    } catch (e) {
      ErrorMessages.logTechnical('confirmCod', e);
      if (!_isCurrent(epoch)) return false;
      _error = 'Could not confirm the cash payment. Please try again.';
      return false;
    } finally {
      if (_isCurrent(epoch)) {
        _confirmingCod = false;
        notifyListeners();
      }
    }
  }

  /// Clears every owner-scoped value when the signed-in identity changes.
  void resetForAccountSwitch() {
    _sessionEpoch++;
    _parkings = const [];
    _bookings = const [];
    _earnings = null;
    _error = null;
    _loading = false;
    _confirmingCod = false;
    notifyListeners();
  }
}
