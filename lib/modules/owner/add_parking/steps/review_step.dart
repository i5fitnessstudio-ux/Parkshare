import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/helpers.dart';
import '../parking_draft.dart';
import '../widgets/photo_preview.dart';

/// Step 10 — Review. Shows the REAL draft (photos + every entered value,
/// including every individual parking space); the publish button uploads photos
/// then creates the listing.
class ReviewStep extends StatelessWidget {
  final ParkingDraft draft;
  final bool isEditing;

  const ReviewStep({super.key, required this.draft, this.isEditing = false});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Review your listing',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          isEditing
              ? 'These are the changes that will be saved. Tap Update Parking '
                    'to apply them.'
              : 'This is exactly what will be published. Tap Publish to upload '
                    'photos and go live.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Photos
        Text(
          'Photos (${draft.photos.length})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        // The REAL uploads: first photo large (BoxFit.cover, rounded), the rest
        // as thumbnails. A neutral tile is shown only while none were added.
        PhotoPreview(
          photos: draft.photos,
          placeholder: const PhotoPreviewPlaceholder(
            label: 'No photo added yet',
          ),
        ),
        const SizedBox(height: 16),

        // Details
        const _SectionTitle('Name & address'),
        _InfoRow('Name', draft.parkingName),
        _InfoRow('Address', draft.address),
        if (draft.city.trim().isNotEmpty) _InfoRow('City', draft.city),
        if (draft.state.trim().isNotEmpty) _InfoRow('State', draft.state),
        if (draft.pincode.trim().isNotEmpty) _InfoRow('Pincode', draft.pincode),
        if (draft.landmark.trim().isNotEmpty)
          _InfoRow('Landmark', draft.landmark),
        const Divider(height: 24),

        // Location
        const _SectionTitle('Location'),
        _InfoRow('Coordinates', '${draft.latitude}, ${draft.longitude}'),
        const Divider(height: 24),

        // Dimensions
        const _SectionTitle('Dimensions'),
        _InfoRow('Parking', _dims(draft.lengthM, draft.widthM, draft.heightM)),
        _InfoRow(
          'Gate / entrance',
          _dims(
            draft.entranceLengthM,
            draft.entranceWidthM,
            draft.entranceHeightM,
          ),
        ),
        const Divider(height: 24),

        // Capacity + the individual spaces
        const _SectionTitle('Capacity & spaces'),
        _InfoRow('Car spaces', '${draft.carSpaceCount}'),
        _InfoRow('Bike spaces', '${draft.bikeSpaceCount}'),
        _InfoRow('Accepts', switch (draft.vehicleType) {
          'BOTH' => 'Bikes & Cars',
          'BIKE' => 'Bikes only',
          _ => 'Cars only',
        }),
        _InfoRow(
          'Mixed parking',
          draft.allowMixedParking ? 'Allowed' : 'Not allowed',
        ),
        const SizedBox(height: 10),
        for (final pool in [
          ('Car', draft.carSpaces),
          ('Bike', draft.bikeSpaces),
        ])
          if (pool.$2.isNotEmpty) ...[
            Text(
              '${pool.$1} spaces',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            for (final s in pool.$2)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ownerPrimaryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.spaceCode,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ownerPrimaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.dimensionLabel +
                            (s.spaceName?.trim().isNotEmpty == true
                                ? ' · ${s.spaceName!.trim()}'
                                : ''),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
          ],
        const Divider(height: 24),

        // Rental — the four independent plans (car/bike × monthly/yearly)
        const _SectionTitle('Rental plans'),
        _InfoRow(
          'Car monthly',
          _plan(draft.carMonthlyEnabled, draft.carMonthlyRent),
        ),
        _InfoRow(
          'Car yearly',
          _plan(draft.carYearlyEnabled, draft.carYearlyRent),
        ),
        _InfoRow(
          'Bike monthly',
          _plan(draft.bikeMonthlyEnabled, draft.bikeMonthlyRent),
        ),
        _InfoRow(
          'Bike yearly',
          _plan(draft.bikeYearlyEnabled, draft.bikeYearlyRent),
        ),
        const Divider(height: 24),

        // Amenities
        const _SectionTitle('Amenities'),
        _InfoRow(
          'Selected',
          draft.amenities.isEmpty ? 'None' : draft.amenities.join(', '),
        ),
        const Divider(height: 24),

        // About
        const _SectionTitle('About'),
        _InfoRow(
          'Parking type',
          draft.parkingType == 'COVERED' ? 'Covered' : 'Open (non-covered)',
        ),
        _InfoRow(
          'Auto-approval',
          draft.autoApproval ? 'On (bookings auto-accepted)' : 'Off',
        ),
        _InfoRow('Access hours', draft.accessHours),
        if (draft.description.trim().isNotEmpty)
          _InfoRow('Description', draft.description),
        if (draft.conditions.trim().isNotEmpty)
          _InfoRow('Conditions', draft.conditions),
      ],
    );
  }

  /// "₹3,500" when the plan is on, "Off" when the owner switched it off.
  String _plan(bool enabled, double? rent) =>
      enabled ? Helpers.formatRupees(rent ?? 0) : 'Off';

  /// Dimensions are stored in meters and shown in FEET everywhere.
  String _dims(double? l, double? w, double? h) {
    if (l == null && w == null && h == null) return '—';
    return 'L ${Helpers.feetLabel(l)} × W ${Helpers.feetLabel(w)} × '
        'H ${Helpers.feetLabel(h)}';
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        color: AppColors.ownerPrimaryDark,
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
