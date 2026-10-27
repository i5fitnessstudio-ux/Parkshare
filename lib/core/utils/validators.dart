import 'package:flutter/material.dart';

/// Shared input validators used by auth forms.
class Validators {
  Validators._();

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _phonePattern = RegExp(r'^[0-9]{6,15}$');

  /// UPI virtual payment address, e.g. `rahul@okhdfcbank`.
  ///
  /// [required] makes it mandatory; omit it to allow an empty optional field.
  /// UPI is optional for all roles as Razorpay Checkout is the primary online
  /// method.
  static String? upiId(String? value, {bool required = true}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? 'UPI ID is required.' : null;
    }
    if (v.length > 64) return 'UPI ID is too long.';
    // Exactly one `@`, handle on the left, provider on the right.
    final pattern = RegExp(r'^[A-Za-z0-9._-]{2,64}@[A-Za-z0-9._-]{2,64}$');
    if (!pattern.hasMatch(v)) {
      return 'Enter a valid UPI ID (e.g. yourname@bank).';
    }
    return null;
  }

  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email is required.';
    if (!_emailPattern.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required.';
    if (v.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value != password) return 'Passwords do not match.';
    return null;
  }

  static String? required(String? value, {String field = 'This field'}) {
    if ((value ?? '').trim().isEmpty) return '$field is required.';
    return null;
  }

  static String? name(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Full name is required.';
    if (v.length < 2) return 'Name must be at least 2 characters.';
    return null;
  }

  static String? phone(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Phone number is required.';
    if (!_phonePattern.hasMatch(v)) return 'Enter a valid phone number.';
    return null;
  }

  /// Indian registration plates: MH12AB1234 / MH 12 AB 1234 / DL-01-ABC-9999.
  static String? registration(String? value) {
    final v = (value ?? '').trim().toUpperCase().replaceAll(
      RegExp(r'[\s-]'),
      '',
    );
    if (v.isEmpty) return 'Registration number is required.';
    if (!RegExp(r'^[A-Z]{2}[0-9]{1,2}[A-Z]{0,3}[0-9]{2,4}$').hasMatch(v)) {
      return 'Enter a valid registration number (e.g. MH12AB1234).';
    }
    return null;
  }
}

/// Small UI helpers.
void showSnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

String friendlyErrorMessage(Object error) {
  if (error is Exception && error.toString().startsWith('Exception:')) {
    return error.toString().replaceFirst('Exception:', '').trim();
  }
  return error.toString();
}
