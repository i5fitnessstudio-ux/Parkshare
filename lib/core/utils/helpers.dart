import 'dart:math' as math;

/// General-purpose helpers (formatting etc.).
class Helpers {
  Helpers._();

  /// Formats a distance in meters into a friendly string.
  /// Always metric — ParkShare uses meters everywhere.
  static String formatDistance(num meters) {
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
  }

  static String formatDate(DateTime date) {
    final d = date.toLocal();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static String formatDateTime(DateTime date) {
    final d = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${formatDate(d)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Formats a rupee amount: 3000 -> "₹3,000", 12345.5 -> "₹12,345.50".
  static String formatRupees(num amount) {
    final fixed = amount % 1 == 0
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    final buffer = StringBuffer();
    final parts = fixed.split('.');
    final whole = parts[0];
    final intPart = whole.replaceAllMapped(
      // Indian grouping: last 3 digits, then pairs from the right.
      RegExp(r'(\d)(?=(?:\d{2})*\d{3}(?!\d))'),
      (m) => '${m[1]},',
    );
    buffer.write(intPart);
    if (parts.length > 1) buffer.write('.${parts[1]}');
    return '₹$buffer';
  }

  /// ParkShare uses meters as the canonical unit. This is a guard for any
  /// accidental mixed-unit measurements (m / cm / feet / inches).
  static String? metersValid(double? value) {
    if (value == null) return 'Measurement is required.';
    if (value.isNaN || value.isInfinite) return 'Invalid measurement.';
    if (value <= 0) return 'Measurement must be greater than 0.';
    if (value > 1000) return 'Measurement looks invalid (> 1000 m).';
    return null;
  }

  // ---------------------------------------------------------------------
  // Feet <-> meters
  //
  // The API, the database and every calculation stay in METERS (the booking
  // fit check, the slot allocator and the vehicle record all speak meters).
  // The owner-facing forms collect FEET, so the conversion happens ONLY at
  // the UI boundary: type feet -> store meters -> display feet again.
  // ---------------------------------------------------------------------
  static const double metersPerFoot = 0.3048;

  /// Meters -> feet (5.00 m -> 16.40).
  static double metersToFeet(double meters) => meters / metersPerFoot;

  /// Feet -> meters (16.40 ft -> 5.00).
  static double feetToMeters(double feet) => feet * metersPerFoot;

  /// "16.40 ft" from a stored measurement, or an em dash when unset.
  static String feetLabel(double? meters, {int decimals = 2}) => meters == null
      ? '—'
      : '${metersToFeet(meters).toStringAsFixed(decimals)} ft';

  /// "53.82 sq ft" from an area held in square meters.
  static String squareFeetLabel(double squareMeters, {int decimals = 2}) =>
      '${(squareMeters / (metersPerFoot * metersPerFoot)).toStringAsFixed(decimals)} sq ft';

  /// Validation for a measurement the owner typed in FEET. Mirrors
  /// [metersValid]; the value is converted to meters right after this runs.
  static String? feetValid(double? value) {
    if (value == null) return 'Measurement is required.';
    if (value.isNaN || value.isInfinite) return 'Invalid measurement.';
    if (value <= 0) return 'Measurement must be greater than 0.';
    if (value > 10000) return 'Measurement looks invalid (> 10000 ft).';
    return null;
  }

  static bool isEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);

  /// Rounded distance between two lat/lng points (haversine), in meters.
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
