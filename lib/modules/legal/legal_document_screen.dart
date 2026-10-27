import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/legal_content.dart';
import '../../shared/widgets/responsive/responsive_layout.dart';

/// Readable, scrollable reader for a [LegalDocument].
///
/// One screen serves both documents so the Terms & Conditions and the Privacy
/// Policy can never drift apart in styling or behaviour. It is reached from the
/// consent links on the Create Account screen (see `TermsConsentCheckbox`) and
/// from the login screens.
///
/// Readability choices, deliberately not the app's dense card style:
///   * an AppBar with the document title, so the user always knows what they
///     are reading and can get back with one tap;
///   * a generous 15.5 px body size, 1.55 line height and a maximum line
///     length, which is what actually makes long legal text readable on a
///     phone;
///   * numbered, tappable-free section headings that stay visible in the
///     scroll flow, with bold lead-ins rather than dense tables.
class LegalDocumentScreen extends StatelessWidget {
  final LegalDocument document;

  /// Accent for the headings: green for the owner surface, blue for the
  /// vehicle-user surface.
  final Color accent;

  const LegalDocumentScreen({
    super.key,
    required this.document,
    this.accent = AppColors.brandBlue,
  });

  /// Convenience named constructors so routes do not need to know which
  /// constant belongs to which screen.
  const LegalDocumentScreen.terms({super.key, Color? accent})
    : document = LegalContent.terms,
      accent = accent ?? AppColors.ownerPrimary;

  const LegalDocumentScreen.privacy({super.key, Color? accent})
    : document = LegalContent.privacy,
      accent = accent ?? AppColors.brandBlue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(
          document.title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        // Long-form legal text: cap at a comfortable reading measure so
        // paragraphs never stretch across a desktop window.
        child: ConstrainedContent(
          maxWidth: ResponsiveLayout.readingMaxWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Text(
                document.lastUpdated,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                document.intro,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.55,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 22),
              for (final section in document.sections) ...[
                _SectionHeading(section: section, accent: accent),
                const SizedBox(height: 8),
                for (final paragraph in section.paragraphs) ...[
                  Text(
                    paragraph,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.55,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
              ],
              const Divider(height: 24),
              Text(
                document.contactHeading,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(height: 10),
              for (final line in document.contact) ...[
                Text(
                  line,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'These documents are provided by the ParkShare app. Keep '
                        'a copy for your records, and contact us if anything '
                        'here is unclear.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final LegalSection section;
  final Color accent;

  const _SectionHeading({required this.section, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            section.number,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            section.heading,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              height: 1.35,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
