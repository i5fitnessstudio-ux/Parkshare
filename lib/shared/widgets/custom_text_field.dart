import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// ParkShare form field with label, icon, validation and error text.
///
/// The text controller is created once (in [State]) so typing stays stable
/// across rebuilds. When [controller] is supplied it is used as-is and owned
/// by the caller; otherwise an internal controller is seeded from
/// [initialValue] and disposed with the widget.
class CustomTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? initialValue;
  final IconData? prefixIcon;
  final IconData? suffixIcon;

  /// Makes [suffixIcon] tappable (e.g. the show/hide password eye). Without
  /// it the icon stays decorative.
  final VoidCallback? onSuffixTap;

  /// Announced by the tappable suffix (screen readers).
  final String? suffixTooltip;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function()? onSubmitted;
  final int maxLines;

  /// Small persistent hint under the field (distinct from [hint], which is
  /// the in-field placeholder that disappears while typing).
  final String? helper;
  final TextStyle? helperStyle;

  /// Greys the field out and blocks input — used while a form is submitting
  /// so a second request cannot be fired.
  final bool enabled;

  const CustomTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.initialValue,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.suffixTooltip,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.helper,
    this.helperStyle,
    this.enabled = true,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  TextEditingController? _internal;

  TextEditingController get _controller =>
      widget.controller ??
      (_internal ??= TextEditingController(text: widget.initialValue ?? ''));

  @override
  void dispose() {
    _internal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: _controller,
          obscureText: widget.obscure,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          validator: widget.validator,
          onChanged: widget.onChanged,
          maxLines: widget.maxLines,
          enabled: widget.enabled,
          onFieldSubmitted: (_) => widget.onSubmitted?.call(),
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(color: AppColors.textHint),
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon, color: colorScheme.primary, size: 22)
                : null,
            suffixIcon: widget.suffixIcon == null
                ? null
                : widget.onSuffixTap == null
                ? Icon(widget.suffixIcon, color: AppColors.warning, size: 18)
                : IconButton(
                    onPressed: widget.onSuffixTap,
                    tooltip: widget.suffixTooltip,
                    icon: Icon(widget.suffixIcon, size: 20),
                    color: colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 48,
                    ),
                  ),
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
              borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.error, width: 1.6),
            ),
          ),
        ),
        // The error text owns this slot while invalid, so the helper text is
        // only rendered when there is no error competing for the same line.
        if (widget.helper != null && widget.helper!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              widget.helper!,
              style:
                  widget.helperStyle ??
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}
