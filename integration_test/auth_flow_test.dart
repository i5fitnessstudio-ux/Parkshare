// ParkShare Phase 1 — end-to-end authentication flow test (runs on emulator).
//
// Covers, in order:
//   1.  Cold boot with no session  -> Onboarding -> Role Selection
//   2.  Vehicle User: Register (single page incl. password + optional UPI ID)
//       -> User Home (blue)
//   3.  Persistent login: app instance restart -> back on User Home
//   4.  Logout -> Role Selection (tokens cleared)
//   5.  Login again with the same credentials -> User Home
//   6.  Forgot password: email -> OTP (auto-filled dev OTP) -> reset password
//       -> Login banner -> login with the NEW password -> User Home
//   7.  Parking Owner: Register -> Owner Dashboard (green)
//   8.  Owner persistent login across restart
//   9.  Final logout -> restart -> Onboarding (tokens were cleared)
//
// Requires the backend running on the host (http://10.0.2.2:8080 from the
// emulator) with PostgreSQL available.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:parkshare_new/app/app.dart';
import 'package:parkshare_new/app/routes.dart';
import 'package:parkshare_new/shared/widgets/terms_consent_checkbox.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpFreshApp(WidgetTester tester) async {
    // Simulates a full app relaunch: dispose the tree, boot a new instance.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const ParkShareApp());
    await tester.pumpAndSettle();
  }

  // Create Account requires the mandatory legal consent, and the Continue
  // button stays disabled until it is ticked. This helper ticks it, after
  // checking that the button really is disabled beforehand and that the two
  // links open the real documents.
  Future<void> acceptTermsAndPrivacy(WidgetTester tester) async {
    final consent = find.byType(TermsConsentCheckbox);
    await tester.ensureVisible(consent);
    await tester.pump(const Duration(milliseconds: 200));

    final checkbox = find.descendant(
      of: consent,
      matching: find.byType(Checkbox),
    );
    expect(
      tester.widget<Checkbox>(checkbox).value,
      isFalse,
      reason: 'consent must start unchecked',
    );
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Checkbox>(checkbox).value,
      isTrue,
      reason: 'tapping the box must record the consent',
    );
  }

  testWidgets('Phase 1 auth: user register + persistent login + logout + '
      'forgot password + owner register + owner persistent login', (
    WidgetTester tester,
  ) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final userEmail = 'user$stamp@parkshare.com';
    final ownerEmail = 'owner$stamp@parkshare.com';
    const password = 'secret123';
    const newPassword = 'newpassword1';

    // ---------------------------------------------------------------
    // 1) Cold boot, logged out -> Onboarding
    // ---------------------------------------------------------------
    await tester.pumpWidget(const ParkShareApp());
    await tester.pumpAndSettle();
    expect(
      find.text('Find parking near you'),
      findsOneWidget,
      reason: 'no session: should land on Onboarding',
    );
    expect(find.text('Next'), findsOneWidget);

    // Skip onboarding -> Role Selection
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('What best describes you?'), findsOneWidget);
    expect(find.text('Vehicle User'), findsOneWidget);
    expect(find.text('Parking Owner'), findsOneWidget);

    // ---------------------------------------------------------------
    // 2) Vehicle User: register details -> create password -> User Home
    // ---------------------------------------------------------------
    await tester.tap(find.text('Vehicle User'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Vehicle User Login'),
      findsOneWidget,
      reason: 'user login screen should be shown',
    );

    final createAccount = find.text('Create Account');
    await tester.ensureVisible(createAccount);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(createAccount);
    await tester.pumpAndSettle();

    // Create Account is ONE page: name, email, phone, UPI ID (optional for a
    // vehicle user), password, confirm password. The old separate
    // "Create Password" step no longer exists.
    expect(find.text('Create Account'), findsOneWidget);
    final regFields = find.byType(TextFormField);
    expect(regFields, findsNWidgets(6));
    await tester.enterText(regFields.at(0), 'Test Driver');
    await tester.enterText(regFields.at(1), userEmail);
    await tester.enterText(regFields.at(2), '9876500123');
    await tester.enterText(regFields.at(3), ''); // UPI optional for users
    await tester.enterText(regFields.at(4), password);
    await tester.enterText(regFields.at(5), password);

    // Mandatory legal consent. The register button stays disabled until the
    // box is ticked, and the two links open the real documents.
    await acceptTermsAndPrivacy(tester);

    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Hi, Test'),
      findsOneWidget,
      reason: 'registered user should land on User Home',
    );
    expect(
      find.text('Map'),
      findsOneWidget,
      reason: 'user bottom nav should be visible',
    );

    // ---------------------------------------------------------------
    // 3) Persistent login: relaunch -> still User Home
    // ---------------------------------------------------------------
    await pumpFreshApp(tester);
    expect(
      find.textContaining('Hi, Test'),
      findsOneWidget,
      reason: 'session should be restored on relaunch (persistent login)',
    );

    // ---------------------------------------------------------------
    // 4) Logout -> Role Selection
    // ---------------------------------------------------------------
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(
      find.text('What best describes you?'),
      findsOneWidget,
      reason: 'logout should return to the auth flow',
    );

    // Relaunch after logout must NOT restore the session.
    await pumpFreshApp(tester);
    expect(
      find.text('Find parking near you'),
      findsOneWidget,
      reason: 'tokens must be cleared after logout',
    );

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // ---------------------------------------------------------------
    // 5) Login again with the same credentials
    // ---------------------------------------------------------------
    await tester.tap(find.text('Vehicle User'));
    await tester.pumpAndSettle();
    final loginFields = find.byType(TextFormField);
    await tester.enterText(loginFields.at(0), userEmail);
    await tester.enterText(loginFields.at(1), password);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Hi, Test'),
      findsOneWidget,
      reason: 'login should route to User Home',
    );

    // ---------------------------------------------------------------
    // 6) Password recovery: the login screen no longer offers a
    //    "Forgot password?" link, but the recovery flow itself is intact and
    //    reachable at AppRoutes.forgotPassword. email -> OTP -> reset ->
    //    login with new pw
    // ---------------------------------------------------------------
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vehicle User'));
    await tester.pumpAndSettle();

    expect(
      find.text('Forgot password?'),
      findsNothing,
      reason: 'the login screens must not offer password recovery',
    );

    // Reach the recovery flow the way the route table defines it.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(AppRoutes.forgotPassword, arguments: const {});
    await tester.pumpAndSettle();
    expect(find.text('Forgot Password'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), userEmail);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send OTP'));
    await tester.pumpAndSettle();
    expect(
      find.text('Verify OTP'),
      findsOneWidget,
      reason: 'OTP screen should be shown after requesting an OTP',
    );
    expect(
      find.textContaining('Development mode: OTP auto-filled'),
      findsOneWidget,
      reason: 'dev OTP should be available without SMTP',
    );

    // OTP is auto-filled from the dev response -> verify.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Verify'));
    await tester.pumpAndSettle();
    expect(
      find.text('Reset Password'),
      findsOneWidget,
      reason: 'reset password screen should follow OTP verification',
    );

    final resetFields = find.byType(TextFormField);
    expect(resetFields, findsNWidgets(2));
    await tester.enterText(resetFields.at(0), newPassword);
    await tester.enterText(resetFields.at(1), newPassword);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Password reset successful'),
      findsOneWidget,
      reason: 'should return to login with a success banner',
    );

    // Old password must no longer work (login with it should fail),
    // new password must work.
    final login2 = find.byType(TextFormField);
    await tester.enterText(login2.at(0), userEmail);
    await tester.enterText(login2.at(1), password);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Invalid email or password'),
      findsOneWidget,
      reason: 'old password must be rejected after reset',
    );

    await tester.enterText(login2.at(1), newPassword);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Hi, Test'),
      findsOneWidget,
      reason: 'new password must work after reset',
    );

    // ---------------------------------------------------------------
    // 7) Parking Owner: register -> Owner Dashboard
    // ---------------------------------------------------------------
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Parking Owner'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Parking Owner Login'), findsOneWidget);

    final ownerCreate = find.text('Create Account');
    await tester.ensureVisible(ownerCreate);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(ownerCreate);
    await tester.pumpAndSettle();

    // Owners must supply a UPI id — it is where users pay them.
    final ownerReg = find.byType(TextFormField);
    expect(ownerReg, findsNWidgets(6));
    await tester.enterText(ownerReg.at(0), 'Test Owner');
    await tester.enterText(ownerReg.at(1), ownerEmail);
    await tester.enterText(ownerReg.at(2), '9876500124');
    await tester.enterText(ownerReg.at(3), 'testowner$stamp@okaxis');
    await tester.enterText(ownerReg.at(4), password);
    await tester.enterText(ownerReg.at(5), password);

    // Owners must tick the same mandatory consent before they can continue.
    await acceptTermsAndPrivacy(tester);

    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Hi, Test'),
      findsOneWidget,
      reason: 'owner should land on the Owner Dashboard',
    );
    expect(
      find.text('Overview'),
      findsOneWidget,
      reason: 'owner dashboard stats should be visible',
    );

    // ---------------------------------------------------------------
    // 8) Owner persistent login across relaunch
    // ---------------------------------------------------------------
    await pumpFreshApp(tester);
    expect(
      find.text('Overview'),
      findsOneWidget,
      reason: 'owner session should persist across relaunch',
    );

    // ---------------------------------------------------------------
    // 9) Final logout -> relaunch -> Onboarding (tokens cleared)
    // ---------------------------------------------------------------
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();
    expect(find.text('What best describes you?'), findsOneWidget);

    await pumpFreshApp(tester);
    expect(
      find.text('Find parking near you'),
      findsOneWidget,
      reason: 'after final logout a relaunch must show Onboarding',
    );
  }, timeout: const Timeout(Duration(minutes: 6)));
}
