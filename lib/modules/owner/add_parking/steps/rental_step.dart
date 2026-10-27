import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../parking_draft.dart';

/// Step 7 — Rental plans: FOUR independent plans (Car/Bike × Monthly/Yearly).
///
/// Each plan has its own switch and its own amount, so an owner can price cars
/// and bikes differently, offer only one period, or leave one vehicle type
/// unbookable. At least one plan must be enabled before publishing; a disabled
/// plan is simply not offered to the user and the server refuses bookings for
/// it. The booking amount is computed server-side.
class RentalStep extends StatelessWidget {
  final ParkingDraft draft;
  final VoidCallback onChanged;

  const RentalStep({super.key, required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Rental plans', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Set the rent for cars and bikes separately, monthly and yearly. '
          'Enable at least one plan — booking amounts are computed '
          'server-side, you only set the rent.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _vehiclePlans(
          context,
          title: 'Car plans',
          icon: Icons.directions_car_outlined,
          monthly: _PlanBinding(
            enabled: draft.carMonthlyEnabled,
            rent: draft.carMonthlyRent,
            onEnabled: (v) {
              draft.carMonthlyEnabled = v;
              onChanged();
            },
            onRent: (v) {
              draft.carMonthlyRent = v;
              onChanged();
            },
          ),
          yearly: _PlanBinding(
            enabled: draft.carYearlyEnabled,
            rent: draft.carYearlyRent,
            onEnabled: (v) {
              draft.carYearlyEnabled = v;
              onChanged();
            },
            onRent: (v) {
              draft.carYearlyRent = v;
              onChanged();
            },
          ),
        ),
        const SizedBox(height: 16),
        _vehiclePlans(
          context,
          title: 'Bike plans',
          icon: Icons.two_wheeler_outlined,
          monthly: _PlanBinding(
            enabled: draft.bikeMonthlyEnabled,
            rent: draft.bikeMonthlyRent,
            onEnabled: (v) {
              draft.bikeMonthlyEnabled = v;
              onChanged();
            },
            onRent: (v) {
              draft.bikeMonthlyRent = v;
              onChanged();
            },
          ),
          yearly: _PlanBinding(
            enabled: draft.bikeYearlyEnabled,
            rent: draft.bikeYearlyRent,
            onEnabled: (v) {
              draft.bikeYearlyEnabled = v;
              onChanged();
            },
            onRent: (v) {
              draft.bikeYearlyRent = v;
              onChanged();
            },
          ),
        ),
      ],
    );
  }

  /// One vehicle type: a titled card holding its Monthly and Yearly plans.
  Widget _vehiclePlans(
    BuildContext context, {
    required String title,
    required IconData icon,
    required _PlanBinding monthly,
    required _PlanBinding yearly,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.ownerPrimary),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _planRow(
            label: 'Monthly',
            icon: Icons.calendar_month_outlined,
            binding: monthly,
          ),
          const Divider(height: 24),
          _planRow(
            label: 'Yearly',
            icon: Icons.event_repeat_outlined,
            binding: yearly,
          ),
        ],
      ),
    );
  }

  /// One plan: title + switch, with its own amount field while enabled.
  Widget _planRow({
    required String label,
    required IconData icon,
    required _PlanBinding binding,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.ownerPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              binding.enabled ? 'On' : 'Off',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: binding.enabled
                    ? AppColors.ownerPrimary
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Switch(
              value: binding.enabled,
              activeTrackColor: AppColors.ownerPrimary,
              onChanged: binding.onEnabled,
            ),
          ],
        ),
        if (binding.enabled) ...[
          const SizedBox(height: 4),
          _AmountField(
            label: '$label rent *',
            initialValue: binding.rent,
            onChanged: binding.onRent,
          ),
        ],
      ],
    );
  }
}

/// The four callbacks/values of one plan, so each row stays readable.
class _PlanBinding {
  final bool enabled;
  final double? rent;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<double?> onRent;

  const _PlanBinding({
    required this.enabled,
    required this.rent,
    required this.onEnabled,
    required this.onRent,
  });
}

/// Rent amount input — one stable controller per card (never recreated on
/// rebuild, otherwise every keystroke would reset the cursor).
class _AmountField extends StatefulWidget {
  final String label;
  final double? initialValue;
  final ValueChanged<double?> onChanged;

  const _AmountField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue == null
          ? ''
          : widget.initialValue!.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => widget.onChanged(double.tryParse(v.trim())),
          decoration: InputDecoration(
            prefixText: '₹ ',
            prefixStyle: const TextStyle(
              color: AppColors.ownerPrimary,
              fontWeight: FontWeight.w700,
            ),
            hintText: '0',
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.ownerPrimary,
                width: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
