import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/helpers.dart';
import '../../../../shared/widgets/dimension_illustration.dart';
import '../../../../shared/widgets/meter_field.dart';
import '../parking_draft.dart';
import '../widgets/photo_preview.dart';

/// Step 4 — Parking dimensions & the entrance (gate).
///
/// Two clearly separated blocks because they answer different questions:
///   * "How big is the whole plot?"  -> the land the owner is renting out
///   * "How wide/tall is the gate?"  -> decides whether anything can get IN
/// Gate width and height are required: without them the server cannot tell a
/// car from a bike at the gate, and a wrong answer means unreachable bookings.
///
/// The plot block leads with the owner's OWN uploaded photo ([PhotoPreview],
/// falling back to the bundled reference illustration only while nothing is
/// uploaded); the gate block keeps its bundled reference image. Both are
/// illustrative — the stored numbers are always the owner-typed ones.
class DimensionsStep extends StatelessWidget {
  final ParkingDraft draft;
  final VoidCallback onChanged;

  const DimensionsStep({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  Widget _sectionTitle(BuildContext context, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.straighten_outlined,
              size: 18,
              color: AppColors.ownerPrimary,
            ),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  /// Preview of the parking: the owner's OWN uploaded photo, large and
  /// cropped, with the rest of the uploads as thumbnails underneath.
  ///
  /// Only while nothing has been uploaded does it fall back to the bundled
  /// reference illustration, so the block is never an empty placeholder once a
  /// photo exists - the owner sees exactly what will be published.
  Widget _parkingPreview() => PhotoPreview(
    photos: draft.photos,
    aspectRatio: 16 / 7,
    placeholder: const DimensionIllustration(
      asset: DimensionIllustration.parkingAsset,
      aspectRatio: DimensionIllustration.parkingAspectRatio,
      placeholderIcon: Icons.local_parking_outlined,
      caption:
          'Reference picture only — it is not to scale and nothing is measured '
          'from it. Enter the real size of your plot below.',
    ),
  );

  /// Professional, locally bundled reference image of the entrance / gate.
  Widget _gateIllustration() => const DimensionIllustration(
    asset: DimensionIllustration.gateAsset,
    aspectRatio: DimensionIllustration.parkingAspectRatio,
    placeholderIcon: Icons.door_front_door_outlined,
    caption:
        'A vehicle wider or taller than the gate can never get in, whatever '
        'the space sizes say.',
  );

  Widget _field({
    required String label,
    required String hint,
    required double? value,
    required ValueChanged<double?> onChanged,
    String? Function(double?)? validator,
  }) => Expanded(
    child: MeterField(
      label: label,
      hint: hint,
      unit: 'ft',
      initialValue: value,
      validator: validator,
      onChanged: onChanged,
    ),
  );

  /// Stores FEET on the field but keeps the draft in METERS (the unit the API,
  /// the fit check and every calculation use).
  void Function(double?) _write(void Function(double?) assign) => (feet) {
    assign(feet == null ? null : Helpers.feetToMeters(feet));
    onChanged();
  };

  /// Feet for the input, meters from the draft.
  double? _read(double? meters) =>
      meters == null ? null : Helpers.metersToFeet(meters);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle(
          context,
          'Parking dimensions',
          'Enter plain numbers in feet — e.g. 16.40 (never "16.40 ft").',
        ),
        const SizedBox(height: 16),
        _parkingPreview(),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
              label: 'Length *',
              hint: '16.40',
              value: _read(draft.lengthM),
              validator: Helpers.feetValid,
              onChanged: _write((v) => draft.lengthM = v),
            ),
            const SizedBox(width: 12),
            _field(
              label: 'Width *',
              hint: '8.20',
              value: _read(draft.widthM),
              validator: Helpers.feetValid,
              onChanged: _write((v) => draft.widthM = v),
            ),
            const SizedBox(width: 12),
            _field(
              label: 'Height *',
              hint: '6.56',
              value: _read(draft.heightM),
              validator: Helpers.feetValid,
              onChanged: _write((v) => draft.heightM = v),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _areaLabel(),
        const SizedBox(height: 28),
        const Divider(height: 1),
        const SizedBox(height: 24),
        _sectionTitle(
          context,
          'Entrance / Gate',
          'The opening vehicles drive through. A vehicle wider or taller than '
              'this can never enter, so these dimensions affect booking '
              'eligibility.',
        ),
        const SizedBox(height: 16),
        _gateIllustration(),
        const SizedBox(height: 20),
        // Same order as the plot block: length, width, height.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
              label: 'Gate length',
              hint: '9.84',
              value: _read(draft.entranceLengthM),
              onChanged: _write((v) => draft.entranceLengthM = v),
            ),
            const SizedBox(width: 12),
            _field(
              label: 'Gate width *',
              hint: '9.20',
              value: _read(draft.entranceWidthM),
              onChanged: _write((v) => draft.entranceWidthM = v),
            ),
            const SizedBox(width: 12),
            _field(
              label: 'Gate height *',
              hint: '7.22',
              value: _read(draft.entranceHeightM),
              onChanged: _write((v) => draft.entranceHeightM = v),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _gateWarning(),
      ],
    );
  }

  /// Live "usable area" readout so the owner can sanity-check the numbers.
  Widget _areaLabel() {
    final l = draft.lengthM;
    final w = draft.widthM;
    if (l == null || w == null || l <= 0 || w <= 0) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Total usable floor area: ${Helpers.squareFeetLabel(l * w)} '
        '(${Helpers.feetLabel(l)} × ${Helpers.feetLabel(w)})',
        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
    );
  }

  /// Warns while the gate is smaller than the plot — the most common cause of
  /// "the car is 5.9 ft wide but the gate says 4.9 ft" surprises.
  Widget _gateWarning() {
    final gw = draft.entranceWidthM;
    final w = draft.widthM;
    if (gw == null || gw <= 0 || w == null || w <= 0 || gw >= w) {
      return const SizedBox.shrink();
    }
    final gateFt = Helpers.metersToFeet(gw).toStringAsFixed(2);
    final plotFt = Helpers.metersToFeet(w).toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Gate width ($gateFt ft) is smaller than the '
              'parking width ($plotFt ft). That is fine, but '
              'only vehicles up to $gateFt ft wide will be '
              'able to enter.',
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
