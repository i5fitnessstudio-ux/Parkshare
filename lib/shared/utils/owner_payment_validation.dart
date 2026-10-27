/// Pure client-side validators for the owner "Payments & Settlements" setup.
///
/// These mirror the backend rules so the form can give immediate, specific
/// feedback — but the backend remains authoritative: it re-validates every
/// field and refuses malformed input regardless of what the app sends.
///
/// Nothing here is about money; no banking value is ever persisted on the
/// device. The full account number / IFSC exist only in the in-memory form
/// state for the duration of the request.
class OwnerPaymentValidation {
  OwnerPaymentValidation._();

  /// RBI IFSC: 4 letters, a literal 0, then 6 alphanumerics.
  static final RegExp ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

  static final RegExp email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Indian bank account numbers are 9-18 digits.
  static final RegExp accountNumber = RegExp(r'^\d{9,18}$');

  /// Indian mobile: 10 digits starting 6-9.
  static final RegExp mobile = RegExp(r'^[6-9]\d{9}$');

  static const List<String> accountTypes = [
    'INDIVIDUAL',
    'PROPRIETOR',
    'COMPANY',
  ];

  static String accountTypeLabel(String type) => switch (type) {
    'INDIVIDUAL' => 'Individual',
    'PROPRIETOR' => 'Proprietor',
    'COMPANY' => 'Company / Business',
    _ => type,
  };

  static String? validateLegalName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Legal account holder name is required.';
    if (v.length < 2) return 'Enter the full legal name.';
    return null;
  }

  static String? validateAccountType(String? value) {
    final v = (value ?? '').trim().toUpperCase();
    if (v.isEmpty) return 'Select an account type.';
    if (!accountTypes.contains(v)) return 'Select a valid account type.';
    return null;
  }

  static String? validateMobile(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'\s|-'), '');
    if (v.isEmpty) return 'Mobile number is required.';
    if (!mobile.hasMatch(v)) return 'Enter a valid 10-digit mobile number.';
    return null;
  }

  static String? validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email is required.';
    if (!email.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  static String? validateAccountHolderName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Bank account holder name is required.';
    if (v.length < 2) return 'Enter the full account holder name.';
    return null;
  }

  static String? validateAccountNumber(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'\s|-'), '');
    if (v.isEmpty) return 'Bank account number is required.';
    if (!accountNumber.hasMatch(v)) {
      return 'Enter a valid bank account number (9-18 digits).';
    }
    return null;
  }

  static String? validateConfirmAccountNumber(String? value, String original) {
    final v = (value ?? '').replaceAll(RegExp(r'\s|-'), '');
    if (v.isEmpty) return 'Please confirm the bank account number.';
    if (v != original.replaceAll(RegExp(r'\s|-'), '')) {
      return 'Bank account numbers do not match.';
    }
    return null;
  }

  static String? validateIfsc(String? value) {
    final v = (value ?? '').trim().toUpperCase().replaceAll(' ', '');
    if (v.isEmpty) return 'IFSC code is required.';
    if (!ifsc.hasMatch(v)) return 'Enter a valid IFSC (e.g. HDFC0001234).';
    return null;
  }

  static String? validateConsent(bool accepted) {
    if (!accepted) return 'Please accept the settlement terms to continue.';
    return null;
  }

  /// Last four digits of a (already validated) account number.
  static String last4(String accountNumber) {
    final v = accountNumber.replaceAll(RegExp(r'\s|-'), '');
    if (v.length <= 4) return v;
    return v.substring(v.length - 4);
  }
}
