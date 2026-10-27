import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Number field for measurements. The label declares the unit ([unit], `ft`
/// for the owner/vehicle forms — the value handed back to the caller is in
/// whatever unit the caller asked for, never a string with the unit appended).
class MeterField extends StatefulWidget {
  final String label;
  final String hint;

  /// Suffix shown in the field: 'ft' for feet, 'm' for meters.
  final String unit;
  final double? initialValue;
  final void Function(double? value) onChanged;
  final String? Function(double? value)? validator;

  const MeterField({
    super.key,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.onChanged,
    this.unit = 'ft',
    this.validator,
  });

  @override
  State<MeterField> createState() => _MeterFieldState();
}

class _MeterFieldState extends State<MeterField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue == null
          ? ''
          : widget.initialValue!.toStringAsFixed(2),
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
          onChanged: (v) {
            widget.onChanged(double.tryParse(v.replaceAll(',', '.').trim()));
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            suffixText: widget.unit,
            suffixStyle: const TextStyle(color: AppColors.textHint),
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
              borderSide: BorderSide(color: AppColors.ownerPrimary, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
