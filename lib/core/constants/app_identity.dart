/// Single source of truth for the Android application identity.
///
/// AUDIT H-07 — `com.parkshare.nexzware` is the stock Flutter template
/// placeholder that ships in `android/app/build.gradle.kts` (`namespace` and
/// `applicationId`). It is reported as a finding rather than silently renamed,
/// because the id is baked into the Play Store listing, any OAuth client id and
/// the map-tile User-Agent string — changing it is a release decision with
/// external consequences. See AUDIT_FIX_LOG.md.
///
/// Before a Play submission, set a real reverse-DNS id in `build.gradle.kts`
/// (and move `android/app/src/main/kotlin/...`) and then update the single value
/// below. Having it here means one edit instead of three scattered literals
/// that can silently drift out of sync — the drift itself was part of the
/// finding.
class AppIdentity {
  AppIdentity._();

  /// Must equal `android/app/build.gradle.kts` -> `defaultConfig.applicationId`.
  ///
  /// Used for:
  ///  * the Esri tile `User-Agent` (`map_tiles.dart`) — the tile terms require
  ///    an *identifying* app identity, and a `com.example.*` placeholder does
  ///    not satisfy that;
  ///  * the `adb shell pm clear` hint printed by the dev reset helper.
  static const String androidPackageName = 'com.parkshare.nexzware';
}
