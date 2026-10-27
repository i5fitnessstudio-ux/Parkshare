import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/photo_picker_service.dart';
import '../../../../shared/widgets/responsive/responsive_layout.dart';
import '../parking_draft.dart';
import '../widgets/photo_preview.dart';

/// Step 1 — Photos. Camera + gallery, preview, remove. PHOTOS ONLY (max 4).
class PhotoStep extends StatelessWidget {
  final ParkingDraft draft;
  final PhotoPickerService picker;
  final VoidCallback onChanged;

  const PhotoStep({
    super.key,
    required this.draft,
    required this.picker,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context, PhotoSource source) async {
    if (draft.photos.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 4 photos allowed.')),
      );
      return;
    }
    final photo = await picker.pick(source);
    if (photo == null) return;
    draft.photos.add(photo);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final count = draft.photos.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          count == 0
              ? 'Add photos of the parking space.'
              : '$count of 4 photos added.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'Photos only (JPG / PNG / WEBP). You can take one with the camera '
          'or pick from the gallery.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        // A photo with no bytes cannot be decoded, so it is never handed to
        // Image.memory — that would throw and take the wizard down.
        if (draft.photos.where((p) => p.bytes.isNotEmpty).isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: PhotoPreviewPlaceholder(
              label:
                  'No photo added yet — take one with the camera or pick '
                  'one from the gallery below.',
            ),
          ),
        ResponsiveGrid(
          // 2 columns on phones; the grid adds columns as the wizard gets
          // wider instead of leaving two oversized tiles on a tablet.
          maxCrossAxisExtent: 240,
          shrinkWrap: true,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            for (final photo in draft.photos)
              if (photo.bytes.isNotEmpty)
                Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(photo.bytes, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () {
                          draft.photos.remove(photo);
                          onChanged();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          ],
        ),
        if (count < 4) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(context, PhotoSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ownerPrimary,
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(context, PhotoSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ownerPrimary,
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
