import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_colors.dart';

/// Mandatory Terms & Conditions / Privacy Policy consent row used by the
/// Create Account screens (both the parking-owner and the vehicle-user one).
///
/// Behaviour:
///   * the checkbox is REQUIRED. It starts unchecked and the caller keeps its
///     own `_acceptedTerms` flag so the submit button can stay disabled until
///     it is ticked;
///   * "Terms & Conditions" and "Privacy Policy" are separately tappable and
///     open the real documents on their own routes. They are real widgets
///     (not recogniser spans inside one Text) so each is its own tap target,
///     its own semantics node, and a tap on a link can never be mistaken for
///     a tap on the checkbox;
///   * tapping the box toggles consent and nothing else;
///   * [accent] tints the tick and the links: green on the owner surface, blue
///     on the vehicle-user surface;
///   * [errorText] carries the friendly "please accept first" message shown
///     after a blocked submit.
class TermsConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// False while a registration request is in flight, which greys out the
  /// checkbox and blocks both links.
  final bool enabled;

  final Color accent;

  /// Optional error copy shown under the row after a blocked submit.
  final String? errorText;

  const TermsConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.accent = AppColors.brandBlue,
    this.errorText,
  });

  void _open(BuildContext context, String route) {
    if (!enabled) return;
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? (v) => onChanged?.call(v ?? false) : null,
              activeColor: accent,
              // Keeps the row compact so it does not eat vertical space on a
              // small phone, and keeps the tick aligned with the first line of
              // the sentence.
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Expanded(
              // A Wrap rather than a single Text.rich: the sentence still
              // flows and re-wraps on a narrow phone, but each link is its own
              // widget with its own hit area.
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Text('I agree to the '),
                  _Link(
                    label: 'Terms & Conditions',
                    accent: accent,
                    enabled: enabled,
                    onTap: () => _open(context, AppRoutes.termsConditions),
                  ),
                  _Text(' and '),
                  _Link(
                    label: 'Privacy Policy',
                    accent: accent,
                    enabled: enabled,
                    onTap: () => _open(context, AppRoutes.privacyPolicy),
                  ),
                  _Text('.'),
                ],
              ),
            ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 2),
            child: Text(
              errorText!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _Text extends StatelessWidget {
  final String text;

  const _Text(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        height: 1.4,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// One tappable document link.
class _Link extends StatelessWidget {
  final String label;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  const _Link({
    required this.label,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            fontWeight: FontWeight.w700,
            color: enabled ? accent : AppColors.textHint,
            decoration: enabled ? TextDecoration.underline : TextDecoration.none,
            decorationColor: accent,
          ),
        ),
      ),
    );
  }
}