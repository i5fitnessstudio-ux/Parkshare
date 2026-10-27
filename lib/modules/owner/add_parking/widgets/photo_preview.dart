import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/photo_picker_service.dart';

/// Preview of the photos the owner has actually uploaded for a parking draft.
///
/// The wizard used to render a static illustration (and, where that asset was
/// missing, a bare placeholder glyph) instead of the owner's own picture, so
/// the "preview" area never showed what would actually be published. This
/// widget renders the real bytes:
///
///   * the FIRST photo is shown large, `BoxFit.cover`, with rounded corners;
///   * any remaining photos appear as a thumbnail strip underneath (and the
///     large one is tap-through to the gallery via [onTap]);
///   * [placeholder] is used ONLY while the draft has no usable photo, so an
///     empty wizard still looks intentional instead of blank;
///   * photos with empty bytes are skipped rather than passed to
///     `Image.memory`, which would otherwise throw on a null/empty path.
///
/// The width always comes from the parent and the height is derived from
/// [aspectRatio], so it scales from a 320 dp phone up to a tablet with no
/// overflow and no hardcoded screen sizes.
class PhotoPreview extends StatelessWidget {
  final List<PickedPhoto> photos;

  /// Rendered only when there is nothing to show. Defaults to a neutral
  /// "no photo yet" tile.
  final Widget? placeholder;

  /// Width / height of the large photo box. Defaults to 16:9.
  final double aspectRatio;

  /// Height of the thumbnail strip under the large photo. 0 hides the strip
  /// (useful where only the hero image is wanted).
  final double thumbnailStripHeight;

  /// Optional tap target on the large photo (e.g. open the full-screen
  /// gallery).
  final VoidCallback? onTap;

  const PhotoPreview({
    super.key,
    required this.photos,
    this.placeholder,
    this.aspectRatio = 16 / 9,
    this.thumbnailStripHeight = 64,
    this.onTap,
  });

  /// Photos that can actually be decoded — an empty byte list would make
  /// `Image.memory` throw, so it is treated as "no photo".
  List<PickedPhoto> get _usable =>
      photos.where((p) => p.bytes.isNotEmpty).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final usable = _usable;
    if (usable.isEmpty) {
      return placeholder ?? const PhotoPreviewPlaceholder();
    }

    final hero = _RoundedPhoto(photo: usable.first);
    final rest = usable.skip(1).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: onTap == null
                    ? hero
                    : InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(14),
                        child: hero,
                      ),
              ),
            ),
            // "1 of N" so the owner can tell which photo they are looking at.
            if (usable.length > 1)
              Positioned(
                right: 8,
                top: 8,
                child: _Badge(
                  child: Text(
                    '1 of ${usable.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (rest.isNotEmpty && thumbnailStripHeight > 0) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: thumbnailStripHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: rest.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(
                width: thumbnailStripHeight,
                child: _RoundedPhoto(photo: rest[i]),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One decoded photo, cropped to fill its box, with rounded corners and a
/// graceful placeholder if the bytes turn out to be undecodable.
class _RoundedPhoto extends StatelessWidget {
  final PickedPhoto photo;

  const _RoundedPhoto({required this.photo});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.memory(
        photo.bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // Never let one corrupt upload blank out the whole preview.
        errorBuilder: (context, error, stack) => const ColoredBox(
          color: AppColors.surface,
          child: Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: AppColors.textHint,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final Widget child;

  const _Badge({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
    );
  }
}

/// Default "nothing uploaded yet" tile: an outlined camera icon plus copy that
/// explains what to do, so an empty wizard never renders as a broken image.
class PhotoPreviewPlaceholder extends StatelessWidget {
  final String label;
  final IconData icon;

  const PhotoPreviewPlaceholder({
    super.key,
    this.label = 'No photo added yet',
    this.icon = Icons.add_a_photo_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 7,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34, color: AppColors.textHint),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
