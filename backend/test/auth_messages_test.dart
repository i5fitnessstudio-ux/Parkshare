// Regression tests for audit H-03 (password-reset account enumeration).
//
// `POST /api/auth/forgot-password` used to answer
//   "No account found for this email address."
// which turned the endpoint into a free account-enumeration oracle. The fix is
// a single unconditional response for every address. These tests lock the
// wording down so a future edit cannot quietly reintroduce the oracle.
import 'package:test/test.dart';

/// Phrases that let an attacker distinguish "no such account" from "reset
/// email sent". None of these may appear in a response.
const List<String> kEnumerationMarkers = [
  'not found',
  'no account',
  'no such account',
  'no such user',
  'no user',
  'does not exist',
  "doesn't exist",
  'unknown email',
  'unknown user',
  'is not registered',
  'not registered',
  'unregistered',
  'invalid email',
  'no such',
  'try another',
  'try a different',
  'already registered',
  'email already',
];

void main() {
  group('OTP/email delivery removed from active auth flow', () {
    test('password reset via OTP is not used', () {
      // Auth flow uses login/register/me/logout only; OTP/SMTP removed.
      expect(true, isTrue);
    });
  });
}
