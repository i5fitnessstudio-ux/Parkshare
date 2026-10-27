import 'package:flutter/material.dart';

/// ParkShare design system colors.
///
/// Owner flows use the green visual system, Vehicle User flows use the
/// blue visual system (per Figma). Neutral colors are shared.
class AppColors {
  AppColors._();

  // ---- Owner (green) ----
  static const Color ownerPrimary = Color(0xFF16A34A);
  static const Color ownerPrimaryDark = Color(0xFF15803D);
  static const Color ownerPrimaryLight = Color(0xFFDCFCE7);

  // ---- Vehicle User (blue) ----
  static const Color userPrimary = Color(0xFF2563EB);
  static const Color userPrimaryDark = Color(0xFF1D4ED8);
  static const Color userPrimaryLight = Color(0xFFDBEAFE);

  // ---- Neutrals ----
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textHint = Color(0xFF94A3B8);
  static const Color border = Color(0xFFE2E8F0);
  static const Color cardShadow = Color(0x140F172A);

  // ---- Semantic ----
  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color info = Color(0xFF2563EB);
  static const Color infoLight = Color(0xFFDBEAFE);
  static const Color disabled = Color(0xFFCBD5E1);

  // ---- Map markers ----
  static const Color parkingMarkerGreen = Color(0xFF16A34A);
  static const Color parkingMarkerGreenDark = Color(0xFF15803D);
  static const Color currentLocationBlue = Color(0xFF2563EB);

  // ---- Shared brand (pre-auth) ----
  static const Color brand = Color(0xFF1F5EBB);
  static const Color brandDark = Color(0xFF0D47A1);
  static const Color brandBlue = Color(0xFF1F5EBB);
}
