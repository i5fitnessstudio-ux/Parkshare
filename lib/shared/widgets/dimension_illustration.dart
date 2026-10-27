import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Instructional illustrations for the Owner wizard's **Dimensions** step.
///
/// Both are *reference images only*: they explain what Length / Width / Height
/// and Gate width / Gate height mean. Nothing is ever measured or calculated
/// from them — the numbers that reach the database are the ones the owner types
/// into the fields below the picture.
///
/// Design rules kept here on purpose:
///   * local assets (`Image.asset`), never `Image.network` — the screen must
///     render identically offline, and the app ships no random stock photos;
///   * responsive — the width comes from the parent and the height is derived
///     from the image's own aspect ratio, so it scales from a 320 dp phone to a
///     tablet with no overflow and no hardcoded screen widths;
///   * `BoxFit.contain` so nothing is ever cropped or distorted.
class DimensionIllustration extends StatelessWidget {
  /// Asset path under `assets/images/`.
  final String asset;

  /// Intrinsic width / height of the PNG. Only used to reserve the right box
  /// before the image has decoded, so the step never jumps.
  final double aspectRatio;

  /// Optional helper line under the picture. Empty hides it.
  final String caption;

  /// Tint applied to the icon shown while the PNG decodes.
  final IconData placeholderIcon;

  const DimensionIllustration({
    super.key,
    required this.asset,
    required this.aspectRatio,
    this.caption = '',
    this.placeholderIcon = Icons.straighten_outlined,
  });

  /// Top-down plan of the whole parking land: length, width, height and the
  /// entrance/gate position.
  static const String parkingAsset = 'assets/images/parking_dimensions.png';

  /// Front elevation of the entrance: a vehicle driving under the gate, with
  /// the gate width and gate height called out.
  static const String gateAsset = 'assets/images/parking_gate_dimensions.png';

  /// 1600 × 700 for both illustrations → 16 : 7.
  static const double parkingAspectRatio = 16 / 7;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // LayoutBuilder + AspectRatio: the picture always takes the full
          // available width and derives its own height, so nothing overflows
          // on a narrow phone and nothing is letterboxed on a wide one.
          LayoutBuilder(
            builder: (context, constraints) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  // A missing/broken asset must never crash the wizard: the
                  // owner still has working number fields underneath.
                  errorBuilder: (context, error, stack) => _fallback(),
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) {
                          return child;
                        }
                        return _fallback();
                      },
                ),
              ),
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fallback() =>
      Center(child: Icon(placeholderIcon, size: 40, color: AppColors.textHint));
}
