import 'package:flutter_map/flutter_map.dart';

import 'app_identity.dart';

/// Tile sources used by the ParkShare maps.
///
/// Both surfaces run on [satellite] (Esri World Imagery) — the Owner
/// "Add Parking > Location" step, where the owner has to recognise a real
/// plot, gate and driveway, and the Vehicle-user main map. [standard] is kept
/// as the plain OpenStreetMap street fallback and is no longer wired into
/// either screen.
///
/// Both are plain XYZ raster endpoints, so swapping a layer is a one-line
/// change and every gesture (pan / pinch / double-tap), marker and camera
/// behaviour is untouched by it.
class MapTiles {
  MapTiles._();

  /// Esri World Imagery — free satellite/aerial tiles, no API key required.
  static const String satelliteUrlTemplate =
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// Highest zoom Esri serves natively; beyond it the app keeps upscaling the
  /// last available tile instead of hitting a 404 on every tile request.
  static const int satelliteMaxNativeZoom = 19;

  static const String satelliteAttribution = 'Esri World Imagery';

  /// Standard OpenStreetMap raster tiles. Kept as the street-map fallback; not
  /// currently wired into a screen.
  static const String standardUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static const int standardMaxNativeZoom = 19;

  static const String standardAttribution = 'OpenStreetMap contributors';

  /// Package name sent as the tile user agent (OSM/Esri tile usage policy).
  ///
  /// AUDIT H-07: sourced from [AppIdentity.androidPackageName] so it cannot
  /// drift from `android/app/build.gradle.kts`. The tile terms require an
  /// *identifying* app identity; while this is still the `com.example.*`
  /// template placeholder, a production tile request does not satisfy that —
  /// a real reverse-DNS id must be set before release.
  static const String userAgentPackageName = AppIdentity.androidPackageName;

  /// Satellite layer — owner "Add Parking > Location" and the vehicle-user map.
  static TileLayer satellite() => TileLayer(
    urlTemplate: satelliteUrlTemplate,
    userAgentPackageName: userAgentPackageName,
    maxNativeZoom: satelliteMaxNativeZoom,
  );

  /// Standard street layer. Retained as a fallback; not currently in use.
  static TileLayer standard() => TileLayer(
    urlTemplate: standardUrlTemplate,
    userAgentPackageName: userAgentPackageName,
    maxNativeZoom: standardMaxNativeZoom,
  );

  static RichAttributionWidget satelliteCredit() =>
      const RichAttributionWidget(
        attributions: [TextSourceAttribution(satelliteAttribution)],
      );

  static RichAttributionWidget standardCredit() =>
      const RichAttributionWidget(
        attributions: [TextSourceAttribution(standardAttribution)],
      );
}