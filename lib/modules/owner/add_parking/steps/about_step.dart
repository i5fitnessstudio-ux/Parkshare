import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../parking_draft.dart';

/// Step 9 — About: parking type, accepted vehicles (read-only, derived from
/// the real parking spaces), auto-approval, access hours, description and
/// conditions.
class AboutStep extends StatelessWidget {
  final ParkingDraft draft;
  final VoidCallback onChanged;

  const AboutStep({super.key, required this.draft, required this.onChanged});

  Widget _segmented<T>({
    required List<(T, String, IconData)> options,
    required T value,
    required ValueChanged<T> onSelected,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final (v, label, icon) in options)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(v),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(
                        icon,
                        color: value == v
                            ? AppColors.ownerPrimary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: value == v
                              ? AppColors.ownerPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Read-only recap of the vehicles this listing can host, derived from the
  /// real slot rows. Tapping "Edit" sends the owner back to the spaces step.
  Widget _acceptsSummary(BuildContext context) {
    final cars = draft.carSpaceCount;
    final bikes = draft.bikeSpaceCount;

    Widget tile(String label, int count, IconData icon) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: count > 0 ? AppColors.ownerPrimary : AppColors.border,
            width: count > 0 ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: count > 0
                  ? AppColors.ownerPrimary
                  : AppColors.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              count > 0 ? '$count' : '0',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: count > 0
                    ? AppColors.ownerPrimary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            tile('Car spaces', cars, Icons.directions_car_outlined),
            const SizedBox(width: 10),
            tile('Bike spaces', bikes, Icons.two_wheeler_outlined),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.ownerPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 16,
                color: AppColors.ownerPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cars + bikes == 0
                      ? 'No parking spaces yet — this listing will not be '
                            'bookable.'
                      : draft.allowMixedParking
                      ? 'Accepts ${cars + bikes} spaces ($cars car, $bikes '
                            'bike) · mixed parking allowed'
                      : 'Accepts ${cars + bikes} spaces ($cars car, $bikes '
                            'bike)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'About this parking',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        const Text(
          'Parking type',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _segmented<String>(
          value: draft.parkingType,
          options: const [
            ('NON_COVERED', 'Open', Icons.wb_sunny_outlined),
            ('COVERED', 'Covered', Icons.roofing_outlined),
          ],
          onSelected: (v) {
            draft.parkingType = v;
            onChanged();
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'Accepts vehicles',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Derived from the parking spaces you added — change the spaces to '
          'change this.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        _acceptsSummary(context),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt_outlined, color: AppColors.ownerPrimary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Auto-approve bookings',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: draft.autoApproval,
                activeTrackColor: AppColors.ownerPrimary,
                onChanged: (v) {
                  draft.autoApproval = v;
                  onChanged();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CustomTextField(
          label: 'Access hours',
          hint: 'e.g. 24/7 or 6 AM - 11 PM',
          initialValue: draft.accessHours == '24/7' ? '' : draft.accessHours,
          onChanged: (v) {
            draft.accessHours = v.trim().isEmpty ? '24/7' : v;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        CustomTextField(
          label: 'Description',
          hint: 'Anything guests should know',
          initialValue: draft.description,
          maxLines: 3,
          onChanged: (v) {
            draft.description = v;
            onChanged();
          },
        ),
        const SizedBox(height: 12),
        CustomTextField(
          label: 'Conditions / house rules',
          hint: 'e.g. no overnight parking',
          initialValue: draft.conditions,
          maxLines: 3,
          onChanged: (v) {
            draft.conditions = v;
            onChanged();
          },
        ),
      ],
    );
  }
}
