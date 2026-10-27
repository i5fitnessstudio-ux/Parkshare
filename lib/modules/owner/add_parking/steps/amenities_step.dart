import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/responsive/responsive_layout.dart';
import '../parking_draft.dart';

/// Step 6 — Amenities. Stored per row in parking_amenities; absence means
/// "not selected". Toggling a chip only reflects when it is checked.
///
/// Tiles are medium-sized (icon + bold label, full-width tap target) and
/// arranged in a responsive 2-column grid so they stay usable and balanced on
/// small screens.
class AmenitiesStep extends StatelessWidget {
  final ParkingDraft draft;
  final VoidCallback onChanged;

  const AmenitiesStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  static const Map<String, IconData> _icons = {
    ParkingAmenity.cctv: Icons.videocam_outlined,
    ParkingAmenity.covered: Icons.roofing_outlined,
    ParkingAmenity.security: Icons.shield_outlined,
    ParkingAmenity.evCharging: Icons.ev_station_outlined,
    ParkingAmenity.lighting: Icons.lightbulb_outline,
    ParkingAmenity.access247: Icons.schedule,
    ParkingAmenity.gateAccess: Icons.lock_outline,
    ParkingAmenity.wheelchair: Icons.accessible,
    ParkingAmenity.waterWash: Icons.water_drop_outlined,
  };

  @override
  Widget build(BuildContext context) {
    // Grow the tile height with the system text scale so the two-line labels
    // can never clip inside a fixed-height cell.
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Amenities', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Select everything this parking offers. Leave unselected anything '
          'it does not have.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        ResponsiveGrid(
          maxCrossAxisExtent: 200,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          // Height tracks the system text scale so larger fonts never clip
          // the two-line labels.
          mainAxisExtent: 84 * textScale,
          shrinkWrap: true,
          children: [
            for (final amenity in ParkingAmenity.all)
              FilterChip(
                label: Text(
                  amenity,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                avatar: Icon(
                  _icons[amenity],
                  size: 22,
                  color: draft.amenities.contains(amenity)
                      ? AppColors.ownerPrimary
                      : AppColors.textSecondary,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 14,
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                selected: draft.amenities.contains(amenity),
                selectedColor: AppColors.ownerPrimaryLight,
                checkmarkColor: AppColors.ownerPrimary,
                showCheckmark: true,
                side: BorderSide(
                  color: draft.amenities.contains(amenity)
                      ? AppColors.ownerPrimary
                      : AppColors.border,
                  width: draft.amenities.contains(amenity) ? 1.6 : 1,
                ),
                onSelected: (selected) {
                  if (selected) {
                    draft.amenities.add(amenity);
                  } else {
                    draft.amenities.remove(amenity);
                  }
                  onChanged();
                },
              ),
          ],
        ),
      ],
    );
  }
}
