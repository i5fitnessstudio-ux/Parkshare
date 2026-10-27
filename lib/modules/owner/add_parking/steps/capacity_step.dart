import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../shared/models/parking_space.dart';
import '../parking_draft.dart';

/// Step 5 — Estimated Capacity.
///
/// The owner states how many cars and how many bikes fit. Those two numbers
/// pre-create the slot rows on the next step ("Parking Spaces"); they are not
/// stored on their own — the server re-derives capacity from the real slots so
/// a hand-edited number can never disagree with the actual list.
class CapacityStep extends StatelessWidget {
  final ParkingDraft draft;
  final VoidCallback onChanged;

  const CapacityStep({super.key, required this.draft, required this.onChanged});

  /// A stepper row with a big touch target, a live "x of y slots" hint and a
  /// clear affordance for 0 (a valid, meaningful answer: "no bike parking").
  Widget _counter({
    required String label,
    required String noun,
    required String type,
    required IconData icon,
    required int value,
    required String helper,
  }) {
    final colour = type == ParkingSpaceVehicleType.bike
        ? AppColors.userPrimary
        : AppColors.ownerPrimary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colour),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value == 0
                          ? 'None'
                          : '$value ${value == 1 ? 'space' : 'spaces'}',
                      style: TextStyle(
                        color: value == 0 ? AppColors.textSecondary : colour,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              _StepButton(
                icon: Icons.remove,
                enabled: value > 0,
                label: 'One fewer $noun',
                onTap: () {
                  draft.setCapacity(type, value - 1);
                  onChanged();
                },
              ),
              const SizedBox(width: 10),
              _StepButton(
                icon: Icons.add,
                enabled: value < 99,
                label: 'One more $noun',
                onTap: () {
                  draft.setCapacity(type, value + 1);
                  onChanged();
                },
                filled: true,
                colour: colour,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              helper,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The real slot-row counts, not a cached counter: the stepper can never
    // disagree with the list the owner sees on the next step.
    final cars = draft.carSpaceCount;
    final bikes = draft.bikeSpaceCount;
    final total = cars + bikes;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Estimated capacity',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'How many separate spaces fit here? Each one is rented out on its '
          'own, so booking one space never blocks the others.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _counter(
          label: 'Car parking spaces',
          noun: 'car space',
          type: ParkingSpaceVehicleType.car,
          icon: Icons.directions_car_outlined,
          value: cars,
          helper: cars == 0
              ? 'No car parking. Only bikes can be booked here.'
              : 'Creates $cars empty car space${cars == 1 ? '' : 's'}. You '
                    'measure each one on the next step — a typical bay is '
                    'about 16.40 × 8.20 ft.',
        ),
        const SizedBox(height: 14),
        _counter(
          label: 'Bike parking spaces',
          noun: 'bike space',
          type: ParkingSpaceVehicleType.bike,
          icon: Icons.two_wheeler_outlined,
          value: bikes,
          helper: bikes == 0
              ? 'No dedicated bike parking. Bikes cannot be booked here.'
              : 'Creates $bikes empty bike space${bikes == 1 ? '' : 's'}. You '
                    'measure each one on the next step — a typical bay is '
                    'about 8.20 × 3.28 ft.',
        ),
        const SizedBox(height: 22),
        if (cars == 0 && bikes == 0)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Add at least one car space or one bike space, otherwise '
                    'nobody can book this parking.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else
          _summary(total: total, cars: cars, bikes: bikes),
        const SizedBox(height: 22),
        _mixedToggle(),
      ],
    );
  }

  Widget _summary({required int total, required int cars, required int bikes}) {
    final label = switch ((cars > 0, bikes > 0)) {
      (true, true) => 'Cars and bikes',
      (true, false) => 'Cars only',
      (false, true) => 'Bikes only',
      _ => '—',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ownerPrimaryLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ownerPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.grid_view_rounded,
                size: 20,
                color: AppColors.ownerPrimaryDark,
              ),
              const SizedBox(width: 8),
              Text(
                '$total total ${total == 1 ? 'space' : 'spaces'}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ownerPrimaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _summaryRow('Car spaces', '$cars'),
          _summaryRow('Bike spaces', '$bikes'),
          _summaryRow('Accepts', label, isLast: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// `allow_mixed_parking` is stored and surfaced (PART 15). It is explicitly
  /// NOT a licence for a car to occupy a bike slot: the server matches vehicle
  /// type to slot type strictly, and the copy says so.
  Widget _mixedToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      // The tile paints its background and ink on the nearest Material, so it
      // gets its own transparent one instead of being hidden by this box.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SwitchListTile(
              value: draft.allowMixedParking,
              activeTrackColor: AppColors.ownerPrimary,
              title: const Text(
                'Allow mixed parking',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Let cars and bikes share the same area when your car spaces '
                'are full.',
                style: TextStyle(fontSize: 12.5),
              ),
              onChanged: (v) {
                draft.allowMixedParking = v;
                onChanged();
              },
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      draft.allowMixedParking
                          ? 'Note: bike spaces stay reserved for bikes. A car '
                                'is never given a bike space, even when they '
                                'are free.'
                          : 'Bike spaces are always reserved for bikes. '
                                'Turning this off does not change that.',
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
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool filled;
  final Color colour;
  final String label;
  final VoidCallback onTap;

  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.label,
    this.filled = false,
    this.colour = AppColors.ownerPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: !enabled
                    ? AppColors.disabled.withValues(alpha: 0.35)
                    : filled
                    ? colour
                    : colour.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: enabled
                      ? (filled ? colour : colour.withValues(alpha: 0.35))
                      : AppColors.border,
                ),
              ),
              child: Icon(
                icon,
                size: 22,
                color: !enabled
                    ? AppColors.textHint
                    : filled
                    ? Colors.white
                    : colour,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
