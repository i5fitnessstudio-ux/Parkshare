import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/helpers.dart';
import '../../../../shared/models/parking_space.dart';
import '../../../../shared/widgets/meter_field.dart';
import '../parking_draft.dart';

/// Step 6 — Parking Spaces: the individual bookable slots.
///
/// Car and bike live in two tabs of ONE step. A type with a capacity of 0 is
/// skipped entirely, so an owner who only rents out bike parking never sees an
/// empty car tab. Every row is a real slot the server allocates to a booking.
class SpacesStep extends StatefulWidget {
  final ParkingDraft draft;
  final VoidCallback onChanged;

  const SpacesStep({super.key, required this.draft, required this.onChanged});

  @override
  State<SpacesStep> createState() => _SpacesStepState();
}

class _SpacesStepState extends State<SpacesStep> {
  late String _tab;

  ParkingDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _tab = _firstAvailableTab();
  }

  /// Car first when both exist, otherwise whichever one does.
  String _firstAvailableTab() => draft.carSpaceCount > 0
      ? ParkingSpaceVehicleType.car
      : ParkingSpaceVehicleType.bike;

  /// A tab is only offered when at least one slot of that type exists, so the
  /// step can never show an empty "Car" tab the owner cannot fill.
  List<String> get _tabs {
    final out = <String>[];
    if (draft.carSpaceCount > 0) out.add(ParkingSpaceVehicleType.car);
    if (draft.bikeSpaceCount > 0) out.add(ParkingSpaceVehicleType.bike);
    return out;
  }

  List<ParkingSpace> get _visible =>
      _tab == ParkingSpaceVehicleType.bike ? draft.bikeSpaces : draft.carSpaces;

  /// Adds one empty slot of the current tab.
  ///
  /// The three measurements are deliberately left BLANK: the size of one bay is
  /// not the size of the whole plot, so the owner has to measure it. A slot that
  /// already exists (an existing listing being edited) keeps its saved values
  /// because only the new row is created here.
  void _addSpace() {
    draft.spaces.add(
      ParkingSpace.draft(
        spaceCode: draft.nextSpaceCode(_tab),
        vehicleType: _tab,
      ),
    );
    // Keep the capacity stepper in step with the real row count.
    draft.syncCapacityCounters();
    widget.onChanged();
  }

  Future<void> _confirmDelete(ParkingSpace space) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${space.spaceCode}?'),
        content: Text(
          'Space ${space.spaceCode} will be removed from this parking. '
          'If it has an active or upcoming booking, it will be kept and you '
          'will be asked to keep it.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      // removeSpace re-numbers the remaining codes (no gap left behind) and
      // re-syncs the stepper counters.
      draft.removeSpace(space);
      if (_tabs.isNotEmpty && !_tabs.contains(_tab)) {
        _tab = _firstAvailableTab();
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    // The step can be re-entered after the capacity step changed the counts.
    if (tabs.isNotEmpty && !tabs.contains(_tab)) {
      _tab = tabs.first;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Parking spaces',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Each space is rented out on its own. Measure every one and '
                'type its own length, width and height — they are never copied '
                'from the total plot size. A vehicle is only offered a space '
                'that is big enough for it and free for the selected dates.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        if (tabs.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _typeTabs(tabs),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: tabs.isEmpty
              ? const _NoSpaces()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    for (final space in _visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SpaceCard(
                          key: ValueKey(space.spaceCode),
                          draft: draft,
                          space: space,
                          type: _tab,
                          index: _visible.indexOf(space) + 1,
                          onDelete: () => _confirmDelete(space),
                          onChanged: widget.onChanged,
                        ),
                      ),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _addSpace,
                      icon: const Icon(Icons.add, size: 20),
                      label: Text(
                        'Add ${ParkingSpaceVehicleType.label(_tab)} Space',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ownerPrimary,
                        side: const BorderSide(color: AppColors.ownerPrimary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _TipsCard(),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _typeTabs(List<String> tabs) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final t in tabs)
            Expanded(
              child: Semantics(
                // container + excludeSemantics: without them this annotation is
                // merged away and a screen reader announces only the count.
                container: true,
                button: true,
                selected: _tab == t,
                excludeSemantics: true,
                label:
                    '${ParkingSpaceVehicleType.label(t)} spaces tab, '
                    '${t == ParkingSpaceVehicleType.bike ? draft.bikeSpaceCount : draft.carSpaceCount}',
                child: GestureDetector(
                  onTap: () => setState(() => _tab = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: _tab == t
                          ? AppColors.ownerPrimary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          t == ParkingSpaceVehicleType.bike
                              ? Icons.two_wheeler
                              : Icons.directions_car,
                          size: 18,
                          color: _tab == t
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${ParkingSpaceVehicleType.label(t)}s '
                            '(${t == ParkingSpaceVehicleType.bike ? draft.bikeSpaceCount : draft.carSpaceCount})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: _tab == t
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One editable slot row: code, optional name, and its three dimensions.
class _SpaceCard extends StatefulWidget {
  final ParkingDraft draft;
  final ParkingSpace space;
  final String type;
  final int index;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _SpaceCard({
    super.key,
    required this.draft,
    required this.space,
    required this.type,
    required this.index,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_SpaceCard> createState() => _SpaceCardState();
}

class _SpaceCardState extends State<_SpaceCard> {
  late final TextEditingController _code;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.space.spaceCode);
    _name = TextEditingController(text: widget.space.spaceName ?? '');
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _applyCode(String raw) {
    final code = raw.trim().toUpperCase();
    final i = widget.draft.spaces.indexOf(widget.space);
    if (i < 0) return;
    widget.draft.spaces[i] = widget.space.copyWith(spaceCode: code);
    widget.onChanged();
  }

  void _applyName(String raw) {
    final i = widget.draft.spaces.indexOf(widget.space);
    if (i < 0) return;
    widget.draft.spaces[i] = widget.space.copyWith(spaceName: raw);
    widget.onChanged();
  }

  /// The owner types FEET; the draft keeps METERS (the unit the API, the
  /// fit check and the slot allocator use).
  void _setLength(double? feet) {
    final i = widget.draft.spaces.indexOf(widget.space);
    if (i < 0) return;
    final s = widget.draft.spaces[i];
    widget.draft.spaces[i] = s.copyWith(
      lengthM: feet == null ? null : Helpers.feetToMeters(feet),
    );
    widget.onChanged();
  }

  void _setWidth(double? feet) {
    final i = widget.draft.spaces.indexOf(widget.space);
    if (i < 0) return;
    final s = widget.draft.spaces[i];
    widget.draft.spaces[i] = s.copyWith(
      widthM: feet == null ? null : Helpers.feetToMeters(feet),
    );
    widget.onChanged();
  }

  void _setHeight(double? feet) {
    final i = widget.draft.spaces.indexOf(widget.space);
    if (i < 0) return;
    final s = widget.draft.spaces[i];
    widget.draft.spaces[i] = s.copyWith(
      heightM: feet == null ? null : Helpers.feetToMeters(feet),
    );
    widget.onChanged();
  }

  /// Meters -> feet for the input; MeterField seeds its text once, on init.
  double? _feet(double? meters) =>
      meters == null ? null : Helpers.metersToFeet(meters);

  @override
  Widget build(BuildContext context) {
    final isBike = widget.type == ParkingSpaceVehicleType.bike;
    final colour = isBike ? AppColors.userPrimary : AppColors.ownerPrimary;
    final s = widget.draft.spaces.firstWhere(
      (e) => identical(e, widget.space),
      orElse: () => widget.space,
    );
    final tooSmall =
        (s.lengthM ?? 0) <= 0 || (s.widthM ?? 0) <= 0 || (s.heightM ?? 0) <= 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tooSmall ? AppColors.warning : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  s.spaceCode,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: colour,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${ParkingSpaceVehicleType.label(widget.type)} space '
                '${widget.index}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Remove this space',
                onPressed: widget.onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                  size: 22,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _TextRow(
                  label: 'Space code',
                  controller: _code,
                  hint: 'C1',
                  textCapitalization: TextCapitalization.characters,
                  onChanged: _applyCode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _TextRow(
                  label: 'Label (optional)',
                  controller: _name,
                  hint: isBike ? 'Near the gate' : 'Corner slot',
                  onChanged: _applyName,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MeterField(
                  label: 'Length *',
                  unit: 'ft',
                  hint: isBike ? '8.20' : '16.40',
                  initialValue: _feet(s.lengthM),
                  onChanged: _setLength,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MeterField(
                  label: 'Width *',
                  unit: 'ft',
                  hint: isBike ? '3.28' : '8.20',
                  initialValue: _feet(s.widthM),
                  onChanged: _setWidth,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MeterField(
                  label: 'Height *',
                  unit: 'ft',
                  hint: isBike ? '6.56' : '7.22',
                  initialValue: _feet(s.heightM),
                  onChanged: _setHeight,
                ),
              ),
            ],
          ),
          if (tooSmall) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 15,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Enter the dimensions for ${widget.draft.labelForSpace(s)}.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TextRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final TextCapitalization textCapitalization;

  const _TextRow({
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
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

/// Explains the slot rules once, where the owner is actually editing slots.
class _TipsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const tips = <(IconData, String)>[
      (
        Icons.straighten_outlined,
        'Size each space accurately. A vehicle is only offered a space that is '
            'at least as long, wide and tall as the vehicle itself.',
      ),
      (
        Icons.door_front_door_outlined,
        'The gate decides access too. A vehicle wider or taller than the gate '
            'cannot enter, whatever the space size says.',
      ),
      (
        Icons.event_available_outlined,
        'Spaces are handed out per booking dates, so one busy space never stops '
            'the others from being booked.',
      ),
      (
        Icons.lock_person_outlined,
        'A space with an active or upcoming booking cannot be deleted — we keep '
            'it so nobody loses their spot.',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ownerPrimaryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 19,
                color: AppColors.ownerPrimaryDark,
              ),
              const SizedBox(width: 8),
              // Flexible so the heading wraps instead of overflowing when the
              // device uses a large accessibility text scale.
              const Expanded(
                child: Text(
                  'Tips for accurate spaces',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ownerPrimaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (icon, text) in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: AppColors.ownerPrimaryDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NoSpaces extends StatelessWidget {
  const _NoSpaces();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.grid_off_outlined,
              size: 46,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 14),
            Text(
              'No parking spaces yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Go back to Estimated Capacity and set at least one car or bike '
              'space.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
