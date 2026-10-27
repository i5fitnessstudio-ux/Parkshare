import 'package:geocoding/geocoding.dart';

/// Result of a place search (forward geocoding) for the map search bar.
class PlaceSearchResult {
  final String name;
  final double latitude;
  final double longitude;
  final String? address;

  const PlaceSearchResult({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
  });

  /// Flutter_map needs [latlong2.LatLng]; keep the dependency out of this
  /// service by returning raw doubles here.
  factory PlaceSearchResult.fromPlacemark(
    Placemark? p, {
    required double lat,
    required double lng,
  }) {
    final parts = [
      p?.name ?? '',
      p?.street ?? '',
      p?.subLocality ?? '',
      p?.locality ?? '',
      p?.administrativeArea ?? '',
      p?.country ?? '',
    ].where((s) => s.trim().isNotEmpty).toList();
    return PlaceSearchResult(
      name: parts.isEmpty ? 'Selected location' : parts.first,
      address: parts.join(', '),
      latitude: lat,
      longitude: lng,
    );
  }
}

/// Forward geocoding ("Search area, street or landmark") using the platform
/// geocoder already wired into the app (`geocoding` package — Android
/// Geocoder / iOS CLGeocoder). Kept as the provider: it is not broken and is
/// free; no paid API is introduced.
///
/// All methods are non-throwing and gracefully handle empty results.
class LocationSearchService {
  /// How long a single platform geocode may take before we treat it as
  /// "not found". Prevents a hung platform geocoder from blocking the map
  /// seed/search forever.
  static const Duration _timeout = Duration(seconds: 6);

  /// Common Tamil Nadu locality tokens. A query mentioning any of these (or a
  /// 6-digit Indian pincode) gets the default region appended so a bare
  /// search like "Anna Nagar" resolves as "Anna Nagar, Tamil Nadu, India".
  /// Queries that already mention a state/country, or a city outside Tamil
  /// Nadu (e.g. "Mumbai"), are left untouched.
  static const Set<String> _tamilNaduHints = {
    'chennai',
    'coimbatore',
    'madurai',
    'trichy',
    'tiruchirappalli',
    'trichirappalli',
    'salem',
    'vellore',
    'tirunelveli',
    'thoothukudi',
    'tuticorin',
    'thanjavur',
    'velachery',
    'adyar',
    'tambaram',
    'chromepet',
    'ambattur',
    'pallavaram',
    'guindy',
    'porur',
    'koyambedu',
    'perungudi',
    'sholinganallur',
    'thiruvanmiyur',
    'besant nagar',
    'bessant nagar',
    'nungambakkam',
    'aminjikarai',
    'egmore',
    'saidapet',
    't nagar',
    'thyagaraya nagar',
    'anna nagar',
    'annanagar',
    'mylapore',
    'kodambakkam',
    'vadapalani',
    'tondiarpet',
    'washermenpet',
    'triplicane',
    'maraimalai nagar',
  };

  /// Indian states / union territories and major cities OUTSIDE Tamil Nadu.
  ///
  /// A query that already names one of these is evidence that it is not a
  /// Tamil Nadu address, so the Tamil Nadu region must NOT be forced onto it.
  /// Without this, a 6-digit pincode alone was enough to turn
  /// "Pipe Road, Kurla West, Mumbai, Maharashtra 400070" into
  /// "… , Tamil Nadu, India" — a wrong region that mislabels the address and
  /// can drag the geocoder to the wrong state entirely.
  ///
  /// Word-boundary matched so a token never fires as a substring of an
  /// unrelated word (e.g. "goa" inside "Goa Hotel" is a match, but
  /// "goatee" is not).
  static final RegExp _nonTamilNaduRegion = RegExp(
    r'\b('
    // States / union territories
    r'maharashtra|karnataka|kerala|telangana|andhra|gujarat|rajasthan|punjab|'
    r'haryana|uttarakhand|himachal pradesh|uttar pradesh|bihar|jharkhand|'
    r'west bengal|odisha|orissa|madhya pradesh|chhattisgarh|goa|assam|'
    r'meghalaya|manipur|mizoram|nagaland|tripura|sikkim|arunachal pradesh|'
    r'ladakh|jammu|kashmir|puducherry|pondicherry|chandigarh|'
    r'andaman|nagar haveli|daman|diu|lakshadweep|delhi'
    // Major cities outside Tamil Nadu
    r'|mumbai|pune|bangalore|bengaluru|hyderabad|ahmedabad|surat|jaipur|'
    r'lucknow|kolkata|patna|nagpur|indore|bhopal|cochin|kochi|kozhikode|'
    r'thiruvananthapuram|trivandrum|visakhapatnam|vijayawada|guwahati|'
    r'chandigarh|dehradun|shimla|panaji|port blair'
    r')\b',
    caseSensitive: false,
  );

  /// Normalises a free-text address query for geocoding WITHOUT changing what
  /// the user sees in the search field.
  ///
  ///  * trims whitespace and collapses runs of spaces inside each part
  ///  * removes empty/duplicate comma-separated parts and trailing commas
  ///  * never appends a region when the query already mentions "India"
  ///  * "… Tamil Nadu" → "… Tamil Nadu, India" (no duplication)
  ///  * a bare Tamil Nadu locality/pincode → "… Tamil Nadu, India"
  ///  * a query naming another Indian state or a non-Tamil-Nadu city is left
  ///    untouched (do not force Tamil Nadu onto "Mumbai" or "Delhi", with or
  ///    without a pincode)
  static String normalizeAddressQuery(String query) {
    final parts = query
        .split(',')
        .map((p) => p.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    var q = parts.join(', ');
    final lower = q.toLowerCase();
    if (lower.contains('india')) return q;
    if (lower.contains('tamil nadu') || lower.contains('tamilnadu')) {
      return '$q, India';
    }
    // Already located outside Tamil Nadu: leave it exactly as typed.
    if (_nonTamilNaduRegion.hasMatch(lower)) return q;
    final hasPincode = RegExp(r'\b\d{6}\b').hasMatch(q);
    final hasTamilNaduHint =
        hasPincode || _tamilNaduHints.any((h) => lower.contains(h));
    if (hasTamilNaduHint) return '$q, Tamil Nadu, India';
    return q;
  }

  /// Geocodes [query] (normalised) and returns the TOP match, or null when
  /// the platform geocoder cannot resolve it. Never throws.
  Future<PlaceSearchResult?> geocodeAddress(String query) async {
    final results = await search(query, limit: 1);
    return results.isEmpty ? null : results.first;
  }

  /// Returns up to [limit] matches for the [query].
  Future<List<PlaceSearchResult>> search(String query, {int limit = 6}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final normalized = normalizeAddressQuery(trimmed);
    if (normalized.isEmpty) return const [];
    try {
      final locations = await locationFromAddress(normalized).timeout(_timeout);
      final results = <PlaceSearchResult>[];
      for (final loc in locations) {
        Placemark? placemark;
        try {
          final marks = await placemarkFromCoordinates(
            loc.latitude,
            loc.longitude,
          ).timeout(_timeout);
          if (marks.isNotEmpty) placemark = marks.first;
        } catch (_) {
          placemark = null;
        }
        results.add(
          PlaceSearchResult.fromPlacemark(
            placemark,
            lat: loc.latitude,
            lng: loc.longitude,
          ),
        );
        if (results.length >= limit) break;
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Reverse geocodes a coordinate into a human-readable location.
  /// Returns null when the platform cannot resolve it (offline, no Geocoder).
  /// Never throws.
  Future<PlaceSearchResult?> reverseGeoCode(
    double latitude,
    double longitude,
  ) async {
    try {
      final marks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(_timeout);
      if (marks.isEmpty) return null;
      return PlaceSearchResult.fromPlacemark(
        marks.first,
        lat: latitude,
        lng: longitude,
      );
    } catch (_) {
      return null;
    }
  }
}
