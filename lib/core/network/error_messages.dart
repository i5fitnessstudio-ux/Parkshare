import 'dart:async';
import 'dart:io';

import 'api_exception.dart';

/// Single place that turns technical failures into short, human-readable UI
/// text. Raw `ApiException(...)`, `SocketException(...)`, `409` or stack-ish
/// strings must never reach a SnackBar/Dialog — the technical detail stays in
/// the debug log (see [logTechnical]).
class ErrorMessages {
  ErrorMessages._();

  // ---- Shared copy (kept identical everywhere on purpose) ----
  static const String generic = 'Something went wrong. Please try again.';
  static const String noInternet = 'No internet connection. Please try again.';
  static const String timeout = 'The request timed out. Please try again.';
  static const String locationUnavailable = 'Unable to load your location.';
  static const String locationPermission =
      'Location access is required to show nearby parking spaces.';
  static const String locationServicesOff =
      'Please enable location services to find parking near you.';
  static const String nearbyFailed = 'Unable to load nearby parking spaces.';
  static const String callFailed = 'Unable to start the call.';
  static const String sessionExpired =
      'Your session has expired. Please sign in again.';
  static const String dateConflict =
      'This parking space is already booked for the selected dates. '
      'Please choose different dates.';

  // ---- Slot-based capacity copy -----------------------------------------
  // A booking takes ONE physical slot, so "full" is per vehicle type and never
  // means the whole property is gone.
  static const String carParkingFull =
      'Car Parking Full. This parking has no car spaces available for your '
      'selected dates. Please choose different dates or another parking '
      'location.';
  static const String bikeParkingFull =
      'Bike Parking Full. This parking has no bike spaces available for your '
      'selected dates. Please choose different dates or another parking '
      'location.';

  /// Shown on Parking Details when slots exist but none of them is big enough
  /// for (or reachable through the gate by) the selected vehicle.
  static const String noSuitableSpace =
      'Your vehicle does not fit any available parking space at this '
      'location.';

  /// The authoritative server-side re-check rejected the booking because the
  /// last matching slot was taken between the probe and the submit. Shown
  /// instead of any technical 409 / ApiException text.
  static const String parkingUnavailable =
      'This parking space was just booked for your selected dates. Please '
      'choose another parking space or different dates.';

  static const String noSpacesAvailable =
      'This parking has no matching parking spaces. Please choose another '
      'parking location.';
  static const String unableToUpdateVehicle =
      'Unable to update vehicle. Please try again.';
  static const String availabilityCheckFailed =
      'We could not check parking availability right now. Please try again.';
  static const String saveParkingFailed =
      'We could not save this parking listing. Please try again.';

  /// Picks the right "full" copy for a vehicle type (PART 18/35).
  static String parkingFull(String? vehicleType) =>
      vehicleType == 'BIKE' ? bikeParkingFull : carParkingFull;

  /// Last line of defence: if a server message ever leaks a technical token
  /// (status code, exception name, socket/stack wording) it is replaced by
  /// [fallback] rather than shown.
  static String sanitize(String? message, String fallback) {
    final first = (message ?? '').split('\n').first.trim();
    if (first.isEmpty || first.length > 300) return fallback;
    final blocked = <String>[
      'apiexception',
      'serverexception',
      'postexception',
      'sockexception',
      'socketsocketexception',
      'http/1.1',
      'stack trace',
      'stacktrace',
      'null check operator',
      'typeerror',
      ' rangeerror',
      'stateerror',
      'unsupportederror',
      'databaseexception',
      'formatException'.toLowerCase(),
      'timeoutException'.toLowerCase(),
      'constraint',
      'relation "',
      'duplicate key',
      'serializationfailure',
    ];
    final lower = first.toLowerCase();
    for (final token in blocked) {
      if (lower.contains(token)) return fallback;
    }
    // A bare "409"/"500"/"400" with no sentence is a status code leaking.
    if (RegExp(r'^\d{3}$').hasMatch(lower)) return fallback;
    return first;
  }

  /// Debug-only breadcrumb. Kept here so call sites read consistently.
  static void logTechnical(String context, Object error) {
    assert(() {
      // ignore: avoid_print
      print('[ErrorMessages] $context -> $error');
      return true;
    }());
  }

  /// Maps any thrown object to text that is safe to show to an end user.
  static String forUi(Object error, {String fallback = generic}) {
    if (error is ApiException) {
      logTechnical('ApiException', error);
      switch (error.type) {
        case ApiErrorType.conflict:
          return sanitize(error.message, dateConflict);
        case ApiErrorType.validation:
          return sanitize(error.message, fallback);
        case ApiErrorType.auth:
          return sessionExpired;
        case ApiErrorType.authorization:
          return sanitize(error.message, 'You are not allowed to do that.');
        case ApiErrorType.notFound:
          return sanitize(error.message, 'The requested item was not found.');
        case ApiErrorType.network:
          return sanitize(error.message, noInternet);
        case ApiErrorType.server:
        case ApiErrorType.unknown:
          return fallback;
      }
    }
    if (error is TimeoutException) return timeout;
    if (error is SocketException) return noInternet;
    if (error is FormatException) return fallback;
    logTechnical('raw', error);
    return fallback;
  }
}
