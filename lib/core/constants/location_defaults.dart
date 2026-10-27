/// Shared map/geocoding defaults.
///
/// ParkShare is a Tamil Nadu (India) focused app. Every map screen that has no
/// better anchor — a previously selected parking coordinate, a valid GPS fix,
/// or a geocodable Step-2 address — must fall back to Tamil Nadu/Chennai and
/// never to any overseas default (e.g. California / Mountain View).
class LocationDefaults {
  LocationDefaults._();

  /// Safe fallback centre: Chennai, Tamil Nadu, India.
  static const double latitude = 13.0827;
  static const double longitude = 80.2707;
}
