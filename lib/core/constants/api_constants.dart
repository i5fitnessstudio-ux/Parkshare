import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// API base URL + endpoint constants.
///
/// Resolution order:
/// 1. `--dart-define=API_BASE_URL=...`
/// 2. Android emulator -> `http://10.0.2.2:8080` (debug only)
/// 3. Desktop / iOS simulator -> `http://localhost:8080` (debug only)
///
/// SECURITY (audit H-08): steps 2 and 3 are *development* defaults. A release
/// build with no explicit `API_BASE_URL` throws in [baseUrl] rather than
/// degrading to a cleartext loopback address that cannot exist on a real
/// device. Use [baseUrlOrNull] / [isHttpsBaseUrl] to assert on the
/// configuration without provoking that throw.
///
/// For a physical Android phone in development:
/// - With ADB reverse, use:
///   --dart-define=API_BASE_URL=http://127.0.0.1:8080
///
/// - With Wi-Fi/LAN, use:
///   --dart-define=API_BASE_URL=http://YOUR_PC_IP:8080
///
/// For a production build, always pass an HTTPS URL:
///   --dart-define=API_BASE_URL=https://api.example.com
class ApiConstants {
  ApiConstants._();

  static const String _overrideBaseUrl =
  String.fromEnvironment('API_BASE_URL');

  /// Emulator loopback alias to the host machine. Debug-only.
  static const String _androidEmulatorBaseUrl = 'http://10.0.2.2:8080';

  /// Desktop / iOS-simulator loopback. Debug-only.
  static const String _localhostBaseUrl = 'http://localhost:8080';

  static String get baseUrl {
    // Highest priority:
    // flutter run --dart-define=API_BASE_URL=http://...
    final override = baseUrlOrNull;
    if (override == null) {
      // SECURITY (audit H-08): a release build with no API_BASE_URL must fail
      // loudly instead of degrading to a cleartext loopback address that
      // cannot exist on a real device.
      throw StateError(
        'API_BASE_URL is not set. Build with '
        '--dart-define=API_BASE_URL=https://<your-api-host>, or run in debug '
        'mode where the emulator/desktop loopback defaults apply.',
      );
    }
    return override;
  }

  /// Same resolution as [baseUrl], but null instead of throwing when a release
  /// build has no explicit `API_BASE_URL`.
  static String? get baseUrlOrNull {
    if (_overrideBaseUrl.isNotEmpty) return _overrideBaseUrl;
    // Audit H-08: no implicit cleartext/loopback default in a release build.
    if (kReleaseMode) return null;
    // Android emulator -> Windows host machine.
    if (!kIsWeb && Platform.isAndroid) {
      return _androidEmulatorBaseUrl;
    }
    // Windows/Desktop/iOS simulator.
    return _localhostBaseUrl;
  }

  /// True when the effective base URL is HTTPS.
  ///
  /// Credentials, tokens and UPI ids must go over TLS in a released app, so this
  /// is the flag a production build is expected to satisfy.
  static bool get isHttpsBaseUrl {
    final url = baseUrlOrNull;
    return url != null && url.toLowerCase().startsWith('https://');
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 25);

  // ============================================================
  // AUTH
  // ============================================================

  static const String register = '/api/auth/register';
  static const String login = '/api/auth/login';
  static const String refresh = '/api/auth/refresh';
  static const String me = '/api/auth/me';
  static const String logout = '/api/auth/logout';

  static const String forgotPassword =
      '/api/auth/forgot-password';

  static const String verifyResetOtp =
      '/api/auth/verify-reset-otp';

  static const String resetPassword =
      '/api/auth/reset-password';

  /// Self-service account deletion (vehicle user OR parking owner).
  ///
  /// The body carries only `password`; the backend derives the account from
  /// the access token, so the client must never send a userId.
  static const String deleteAccount = '/api/account';

  // ============================================================
  // PARKING
  // ============================================================

  static const String parkings = '/api/parkings';
  static const String uploadPhoto = '/api/uploads';

  static String parkingById(
      String id, {
        String? vehicleId,
        DateTime? startDate,
        DateTime? endDate,
      }) {
    return _withQuery(
      '/api/parkings/$id',
      vehicleId: vehicleId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  static String ownerParkings(String ownerId) {
    return '/api/parkings/owner/$ownerId';
  }

  /// Individual physical parking slots:
  /// C1, C2, B1, B2, etc.
  static String parkingSpaces(
      String parkingId, {
        String? vehicleId,
        DateTime? startDate,
        DateTime? endDate,
      }) {
    return _withQuery(
      '/api/parkings/$parkingId/spaces',
      vehicleId: vehicleId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  static String nearbyParkings({
    required double lat,
    required double lng,
    double radiusKm = 5,
    String? vehicleId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _withQuery(
      '/api/parkings/nearby'
          '?lat=$lat'
          '&lng=$lng'
          '&radiusKm=$radiusKm',
      vehicleId: vehicleId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// Read-only availability check.
  ///
  /// Final authoritative booking availability must still
  /// be checked by the backend during booking creation.
  static String parkingAvailability({
    required String id,
    required String startDate,
    required String endDate,
    String? vehicleId,
    String? vehicleType,
  }) {
    return _withQuery(
      '/api/parkings/$id/availability'
          '?startDate=$startDate'
          '&endDate=$endDate',
      vehicleId: vehicleId,
      vehicleType: vehicleType,
    );
  }

  // ============================================================
  // VEHICLES
  // ============================================================

  static const String vehicles = '/api/vehicles';

  static String vehicleById(String id) {
    return '/api/vehicles/$id';
  }

  // ============================================================
  // BOOKINGS
  // ============================================================

  static const String bookings = '/api/bookings';

  static String ownerBookings(String ownerId) {
    return '/api/bookings/owner/$ownerId';
  }

  static String userBookings(String userId) {
    return '/api/bookings/user/$userId';
  }

  static String bookingById(String id) {
    return '/api/bookings/$id';
  }

  static String acceptBooking(String id) {
    return '/api/bookings/$id/accept';
  }

  static String rejectBooking(String id) {
    return '/api/bookings/$id/reject';
  }

  // ============================================================
  // PAYMENTS
  // ONLINE (RAZORPAY) + CASH ON DELIVERY
  // ============================================================

  static const String payments = '/api/payments';

  /// Returns the selected parking owner's:
  /// - owner name
  /// - phone
  /// - other payment/contact details
  static String parkingOwnerPaymentInfo(String parkingId) {
    return '/api/payments/parking/$parkingId/owner';
  }

  /// Server-computed owner settlement totals (Total Earnings, pending counts).
  ///
  /// Owner-only. Audit C-02: the dashboard used to derive this figure from the
  /// bookings it happened to have loaded.
  static const String ownerEarnings = '/api/payments/owner/earnings';

  /// Owner payment / settlement account status (masked).
  ///
  /// Owner-only. `GET` loads the masked status, `PUT`/`POST` save the setup.
  /// The owner id always comes from the JWT — never from the path or body — so
  /// one owner can never read or edit another owner's setup. The response never
  /// carries a full bank account number, IFSC, PAN/KYC or linked-account id.
  static const String ownerPaymentAccount =
      '/api/payments/owner/payment-account';

  /// User chooses Cash on Delivery.
  ///
  /// Booking should remain COD_PENDING until
  /// owner confirms that cash has been received.
  static const String cod =
      '/api/payments/cod';

  /// Owner confirms cash was received.
  ///
  /// After successful confirmation:
  /// - payment -> COD_CONFIRMED
  /// - booking -> CONFIRMED
  /// - earnings updated
  static String confirmCod(String bookingId) {
    return '/api/payments/$bookingId/cod/confirm';
  }

  /// Creates a server-authoritative Razorpay order for a booking.
  ///
  /// The backend reads the amount from the booking row; the client must never
  /// send an amount. The response carries the public `razorpayKeyId`, the
  /// `razorpayOrderId` and the integer `amount` in paise.
  static const String razorpayOrder = '/api/payments/razorpay/order';

  /// Verifies a Razorpay Checkout callback signature on the backend.
  ///
  /// The backend recomputes `HMAC_SHA256(orderId|paymentId, keySecret)` and
  /// only then marks the booking paid. The client never verifies a signature.
  static const String razorpayVerify = '/api/payments/razorpay/verify';

  // ============================================================
  // RAZORPAY WEBHOOKS
  // ============================================================

  /// Razorpay -> ParkShare webhook. Authenticated by the
  /// `X-Razorpay-Signature` HMAC only (never a user JWT). Not called by the app.
  static const String razorpayWebhook = '/api/webhooks/razorpay';

  // ============================================================
  // INBOX / CHAT
  // ============================================================

  static const String conversations =
      '/api/inbox/conversations';

  static String conversationMessages(String id) {
    return '/api/inbox/conversations/$id/messages';
  }

  // ============================================================
  // QUERY HELPERS
  // ============================================================

  /// Adds optional query parameters without overwriting
  /// parameters already present in [path].
  static String _withQuery(
      String path, {
        String? vehicleId,
        String? vehicleType,
        DateTime? startDate,
        DateTime? endDate,
      }) {
    final params = <String>[];

    void add(String key, String? value) {
      final valueToAdd = value?.trim() ?? '';

      if (valueToAdd.isEmpty) {
        return;
      }

      params.add(
        '$key=${Uri.encodeComponent(valueToAdd)}',
      );
    }

    add('vehicleId', vehicleId);
    add('vehicleType', vehicleType);
    add('startDate', _isoDate(startDate));
    add('endDate', _isoDate(endDate));

    if (params.isEmpty) {
      return path;
    }

    final separator = path.contains('?') ? '&' : '?';

    return '$path$separator${params.join('&')}';
  }

  /// Converts DateTime to YYYY-MM-DD.
  static String? _isoDate(DateTime? date) {
    if (date == null) {
      return null;
    }

    final year =
    date.year.toString().padLeft(4, '0');

    final month =
    date.month.toString().padLeft(2, '0');

    final day =
    date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
