import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/data/indian_states_cities.dart';
import '../../../../shared/widgets/custom_text_field.dart';
import '../parking_draft.dart';

/// Step 2 — Basic details (name + address required).
///
/// City and State are searchable: typing filters a predefined Indian place
/// list and tapping a suggestion fills the field (the owner can still type a
/// place that is not on the list — nothing is ever forced).
class DetailsStep extends StatelessWidget {
  final ParkingDraft draft;
  final VoidCallback onChanged;

  const DetailsStep({super.key, required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Name & address', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        CustomTextField(
          label: 'Parking space name *',
          hint: 'e.g. Greenview Secure Parking',
          initialValue: draft.parkingName,
          onChanged: (v) {
            draft.parkingName = v;
            onChanged();
          },
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        CustomTextField(
          label: 'Address *',
          hint: 'Street, building, area',
          initialValue: draft.address,
          onChanged: (v) {
            draft.address = v;
            onChanged();
          },
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StateField(
                initialValue: draft.state,
                onChanged: (v) {
                  draft.state = v;
                  // Reset city when state changes
                  draft.city = '';
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CityField(
                state: draft.state,
                initialValue: draft.city,
                onChanged: (v) {
                  draft.city = v;
                  onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CustomTextField(
                label: 'Pincode',
                hint: '400001',
                keyboardType: TextInputType.number,
                initialValue: draft.pincode,
                onChanged: (v) {
                  draft.pincode = v;
                  onChanged();
                },
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                label: 'Landmark',
                hint: 'Near the signal',
                initialValue: draft.landmark,
                onChanged: (v) {
                  draft.landmark = v;
                  onChanged();
                },
                textInputAction: TextInputAction.done,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Fields marked * are required.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

/// Text field with a searchable suggestion dropdown (Indian cities / states).
///
/// Styling matches [CustomTextField] so the row keeps its balanced look; the
/// suggestions float in an overlay that never shifts the layout.
InputDecoration get _decoration => InputDecoration(
  hintText: '',
  hintStyle: const TextStyle(color: AppColors.textHint),
  suffixIcon: const Icon(
    Icons.arrow_drop_down,
    color: AppColors.textSecondary,
    size: 24,
  ),
  filled: true,
  fillColor: AppColors.surface,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.ownerPrimary, width: 1.6),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.error),
  ),
  focusedErrorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.error, width: 1.6),
  ),
);

class _StateField extends StatelessWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;

  const _StateField({required this.initialValue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'State',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        RawAutocomplete<String>(
          initialValue: TextEditingValue(text: initialValue),
          optionsBuilder: (textEditingValue) => IndianStatesCities.match(
            textEditingValue.text,
            IndianStatesCities.states,
          ),
          onSelected: onChanged,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.next,
              onChanged: onChanged,
              onSubmitted: (_) => onFieldSubmitted(),
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
              decoration: _decoration.copyWith(hintText: 'Maharashtra'),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList(growable: false);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final option = list[index];
                      final highlighted =
                          AutocompleteHighlightedOption.of(context) == index;
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Container(
                          width: double.infinity,
                          color: highlighted
                              ? AppColors.ownerPrimaryLight
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Text(
                            option,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CityField extends StatelessWidget {
  final String state;
  final String initialValue;
  final ValueChanged<String> onChanged;

  const _CityField({
    required this.state,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cities = IndianStatesCities.getCitiesForState(state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'City',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        RawAutocomplete<String>(
          key: ValueKey('city_$state'),
          initialValue: TextEditingValue(text: initialValue),
          optionsBuilder: (textEditingValue) =>
              IndianStatesCities.match(textEditingValue.text, cities),
          onSelected: onChanged,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.next,
              onChanged: onChanged,
              onSubmitted: (_) => onFieldSubmitted(),
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
              decoration: _decoration.copyWith(hintText: 'Mumbai'),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList(growable: false);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final option = list[index];
                      final highlighted =
                          AutocompleteHighlightedOption.of(context) == index;
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Container(
                          width: double.infinity,
                          color: highlighted
                              ? AppColors.ownerPrimaryLight
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Text(
                            option,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
