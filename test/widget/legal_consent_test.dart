// Widget tests for the mandatory Terms & Conditions / Privacy Policy consent
// gate on the Create Account screen, and for the two legal documents
// themselves.
//
// These cover what would regress silently: a button that becomes enabled
// without the tick, a link that does not actually open a document, a document
// that renders no sections, and owner/user accent drift.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkshare_new/app/routes.dart';
import 'package:parkshare_new/core/constants/app_colors.dart';
import 'package:parkshare_new/core/constants/app_strings.dart';
import 'package:parkshare_new/core/constants/legal_content.dart';
import 'package:parkshare_new/modules/auth/screens/register_screen.dart';
import 'package:parkshare_new/modules/legal/legal_document_screen.dart';
import 'package:parkshare_new/modules/shared/providers/location_provider.dart';
import 'package:parkshare_new/modules/user/providers/user_map_provider.dart';
import 'package:parkshare_new/shared/models/user.dart';
import 'package:parkshare_new/shared/widgets/terms_consent_checkbox.dart';
import 'package:provider/provider.dart';

/// Register screen inside a navigator that mirrors the app's route table for
/// the two legal routes, plus the providers the screen reads.
Widget host(String? role) => MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => LocationProvider()),
    ChangeNotifierProvider(create: (_) => UserMapProvider()),
  ],
  child: MaterialApp(
    initialRoute: AppRoutes.register,
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => switch (settings.name) {
        AppRoutes.termsConditions => const LegalDocumentScreen.terms(),
        AppRoutes.privacyPolicy => const LegalDocumentScreen.privacy(),
        _ => RegisterScreen(role: role),
      },
    ),
  ),
);

void main() {
  Finder consentBox() => find.descendant(
    of: find.byType(TermsConsentCheckbox),
    matching: find.byType(Checkbox),
  );

  Finder continueButton() => find.widgetWithText(ElevatedButton, 'Continue');

  /// Scrolls the consent row into view and taps it. The row sits below the
  /// fold of the register form, so a bare tap would land on the wrong widget.
  Future<void> tapConsent(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(TermsConsentCheckbox));
    await tester.pumpAndSettle();
    await tester.tap(consentBox());
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(WidgetTester tester, {required bool owner}) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Test Person');
    await tester
        .enterText(fields.at(1), owner ? 'owner@ok.com' : 'user@ok.com');
    await tester.enterText(fields.at(2), '9876500000');
    await tester.enterText(fields.at(3), owner ? 'person@okaxis' : '');
    await tester.enterText(fields.at(4), 'secret123');
    await tester.enterText(fields.at(5), 'secret123');
    await tester.pumpAndSettle();
  }

  group('Create Account legal consent', () {
    for (final role in [UserRole.user, UserRole.owner]) {
      final label = role == UserRole.owner ? 'parking owner' : 'vehicle user';

      testWidgets('$label cannot continue until the consent box is ticked', (
        tester,
      ) async {
        await tester.pumpWidget(host(role));
        await fillForm(tester, owner: role == UserRole.owner);

        expect(find.byType(TermsConsentCheckbox), findsOneWidget);
        expect(
          tester.widget<Checkbox>(consentBox()).value,
          isFalse,
          reason: 'consent must start unchecked',
        );
        expect(
          tester.widget<ElevatedButton>(continueButton()).onPressed,
          isNull,
          reason: 'the button must be disabled before consent',
        );

        await tapConsent(tester);
        expect(
          tester.widget<ElevatedButton>(continueButton()).onPressed,
          isNotNull,
          reason: 'consent must unlock the button',
        );
      });

      testWidgets('$label sees a friendly message on a blocked submit', (
        tester,
      ) async {
        await tester.pumpWidget(host(role));
        await fillForm(tester, owner: role == UserRole.owner);

        // The disabled button swallows a tap, so the guard is exercised the way
        // a keyboard user reaches it: submitting from the last field.
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.text(AppStrings.consentRequired), findsOneWidget);
        expect(
          find.text('Create Account'),
          findsOneWidget,
          reason: 'still on Create Account: no account was created',
        );
      });

      testWidgets('$label accent tints the consent checkbox', (tester) async {
        await tester.pumpWidget(host(role));
        expect(
          tester.widget<Checkbox>(consentBox()).activeColor,
          role == UserRole.owner
              ? AppColors.ownerPrimary
              : AppColors.brandBlue,
        );
      });
    }

    for (final role in [UserRole.user, UserRole.owner]) {
      final label = role == UserRole.owner ? 'parking owner' : 'vehicle user';

      testWidgets('$label signup links open the real documents and neither '
          'consents', (tester) async {
        await tester.pumpWidget(host(role));
        await tester.pumpAndSettle();

        final termsLink = find.text('Terms & Conditions');
        final privacyLink = find.text('Privacy Policy');

        await tester.ensureVisible(termsLink);
        await tester.pumpAndSettle();
        await tester.tap(termsLink);
        await tester.pumpAndSettle();
        expect(
          find.text(LegalContent.terms.title),
          findsOneWidget,
          reason: 'the terms link must open the Terms document',
        );
        expect(find.text(LegalContent.terms.lastUpdated), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.ensureVisible(privacyLink);
        await tester.pumpAndSettle();
        await tester.tap(privacyLink);
        await tester.pumpAndSettle();
        expect(
          find.text(LegalContent.privacy.title),
          findsOneWidget,
          reason: 'the privacy link must open the Privacy document',
        );

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester.widget<Checkbox>(consentBox()).value,
          isFalse,
          reason: 'reading a document must not tick the box',
        );
        expect(
          tester.widget<ElevatedButton>(continueButton()).onPressed,
          isNull,
          reason: 'the button must still be blocked',
        );
      });
    }

    testWidgets('unticking the box re-blocks the button', (tester) async {
      await tester.pumpWidget(host(UserRole.user));
      await fillForm(tester, owner: false);

      await tapConsent(tester);
      expect(tester.widget<ElevatedButton>(continueButton()).onPressed,
          isNotNull);

      await tapConsent(tester);
      expect(
        tester.widget<ElevatedButton>(continueButton()).onPressed,
        isNull,
      );
    });
  });

  group('Legal documents', () {
    test('both documents have 11 numbered sections and a contact block', () {
      for (final doc in [LegalContent.terms, LegalContent.privacy]) {
        expect(doc.sections, hasLength(11), reason: '${doc.title} sections');
        expect(doc.sections.first.number, '1');
        expect(doc.sections.last.number, '11');
        for (final s in doc.sections) {
          expect(s.heading, isNotEmpty, reason: '${doc.title} ${s.number}');
          expect(
            s.paragraphs,
            isNotEmpty,
            reason: '${doc.title} section ${s.number} body',
          );
        }
        expect(doc.contactHeading, 'Contact Us');
        expect(doc.contact, isNotEmpty);
        expect(doc.lastUpdated, startsWith('Last updated:'));
      }
    });

    test('the documents are titled as the app advertises them', () {
      expect(LegalContent.terms.title, 'ParkShare Terms & Conditions');
      expect(LegalContent.privacy.title, 'ParkShare Privacy Policy');
      expect(
        LegalContent.terms.title,
        isNot(LegalContent.privacy.title),
        reason: 'the two routes must never point at the same document',
      );
    });

    testWidgets('the Terms screen renders every heading without overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: LegalDocumentScreen.terms()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final s in LegalContent.terms.sections) {
        await tester.scrollUntilVisible(
          find.text(s.heading),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(s.heading), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.text('Contact Us'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Contact Us'), findsOneWidget);
      expect(
        find.text('Email: ${LegalContent.supportEmail}'),
        findsOneWidget,
      );
      expect(
        find.text('Phone: ${LegalContent.supportPhone}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    test('both documents advertise the current support contact', () {
      for (final doc in [LegalContent.terms, LegalContent.privacy]) {
        expect(doc.contactHeading, 'Contact Us');
        expect(
          doc.contact,
          contains('Email: ${LegalContent.supportEmail}'),
          reason: '${doc.title} email',
        );
        expect(
          doc.contact,
          contains('Phone: ${LegalContent.supportPhone}'),
          reason: '${doc.title} phone',
        );
      }
      expect(LegalContent.supportEmail, 'info@nexzware.com');
      expect(LegalContent.supportPhone, '+91 9791070214');
    });

    testWidgets('the Privacy screen shows the updated contact block', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: LegalDocumentScreen.privacy()),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Contact Us'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Contact Us'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Email: ${LegalContent.supportEmail}'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Email: ${LegalContent.supportEmail}'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Phone: ${LegalContent.supportPhone}'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Phone: ${LegalContent.supportPhone}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Privacy screen renders its first section', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: LegalDocumentScreen.privacy()),
      );
      await tester.pumpAndSettle();
      expect(find.text(LegalContent.privacy.sections.first.heading),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}