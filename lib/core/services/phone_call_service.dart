import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Outcome of a dial attempt, so the UI can show the right message.
enum PhoneCallResult {
  /// The native dialler was opened with the number pre-filled.
  launched,

  /// No usable phone number on record for this contact.
  unavailableNumber,

  /// Android reported no dialler app that can handle `tel:`.
  noDialer,

  /// The launcher threw / the user cancelled.
  failed,
}

/// Opens the NATIVE Android dialler (`tel:<number>`) for a contact resolved
/// from the booking relationships.
///
/// The dialler is only pre-filled — the user still presses the actual call
/// button, so **no CALL_PHONE runtime permission is required** (and none is
/// declared in AndroidManifest.xml).
class PhoneCallService {
  PhoneCallService._();

  /// Normalises a stored phone number: keeps digits and one leading `+`,
  /// drops spaces / dashes / brackets. Returns null when nothing is dialable.
  static String? normalize(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final ch = value[i];
      if (ch == '+' && buffer.isEmpty) {
        buffer.write(ch);
      } else if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
        buffer.write(ch);
      }
    }
    final digits = buffer.toString();
    if (digits.isEmpty || digits == '+') return null;
    return digits;
  }

  /// Launches the dialler for [phone]. Never throws.
  static Future<PhoneCallResult> dial(String? phone) async {
    final number = normalize(phone);
    if (number == null) return PhoneCallResult.unavailableNumber;
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final ok = await launchUrl(uri);
      return ok ? PhoneCallResult.launched : PhoneCallResult.noDialer;
    } catch (e) {
      debugPrint('[PhoneCallService] dial($number) failed: $e');
      return PhoneCallResult.failed;
    }
  }
}
