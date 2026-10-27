import 'package:flutter/foundation.dart';

/// Build-time flags that must never widen in a production build.
///
/// SECURITY (audit H-02 / H-08). These exist so that the local password-reset
/// flow stays testable without leaving a hole in a shipped binary:
///
/// * The backend only ever returns a `devOtp` when `APP_ENV` is not production
///   **and** `ALLOW_DEV_OTP=true` **and** no SMTP transport is configured
///   (see `backend/lib/config/config.dart`, `Config.allowDevOtp`).
/// * The app only ever *displays* it under [DevFlags.devOtpEnabled], which
///   requires a debug build **and** an explicit
///   `--dart-define=ALLOW_DEV_OTP=true`.
///
/// Both sides therefore have to agree, and a release build can satisfy neither.
/// `kDebugMode` (not `kReleaseMode`) is the primary guard so that a
/// profile-mode build — which has `kReleaseMode == true` — also stays safe.
///
/// Usage:
/// ```
/// flutter run --dart-define=ALLOW_DEV_OTP=true
/// ```
class DevFlags {
  DevFlags._();

  /// Opt-in, set at build time: `--dart-define=ALLOW_DEV_OTP=true`.
  static const bool _allowDevOtpRequested =
      bool.fromEnvironment('ALLOW_DEV_OTP');

  /// True only in a debug/profile build that explicitly asked for it.
  ///
  /// Never true in a release build, no matter what was passed at build time —
  /// a stray `--dart-define` on a release pipeline therefore cannot re-enable
  /// OTP display.
  static bool get devOtpEnabled => kDebugMode && _allowDevOtpRequested;

  /// Whether the "Development mode" banner should be visible.
  ///
  /// Separate from [devOtpEnabled] only so the banner has a single named
  /// predicate to read; the logic is intentionally identical.
  static bool get showDevOtpBanner => devOtpEnabled;
}