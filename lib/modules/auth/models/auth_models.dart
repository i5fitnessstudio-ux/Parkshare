import '../../../shared/models/user.dart';

/// Result of register / login / refresh.
class AuthResult {
  final User user;
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  const AuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      user: User.fromJson((json['user'] as Map<String, dynamic>?) ?? {}),
      accessToken: json['accessToken']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString() ?? '',
      accessExpiresAt:
          DateTime.tryParse(json['accessExpiresAt']?.toString() ?? '') ??
          DateTime.now(),
      refreshExpiresAt:
          DateTime.tryParse(json['refreshExpiresAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Result of forgot-password.
///
/// SECURITY (audit H-03): `email` is echoed back but the *message* is the
/// backend's single shared wording, so this object is identical for a
/// registered and an unregistered address.
///
/// SECURITY (audit H-02): [devOtp] is only ever populated by the backend when
/// `ALLOW_DEV_OTP=true` and no SMTP transport exists. Parsing it here keeps the
/// value available for local testing; whether it reaches the UI is decided by
/// `DevFlags.devOtpEnabled`, and nothing here logs or persists it.
class ForgotPasswordResult {
  final String email;
  final int ttlMinutes;

  /// Development-only OTP echo. Never present in a production response.
  final String? devOtp;

  const ForgotPasswordResult({
    required this.email,
    required this.ttlMinutes,
    this.devOtp,
  });

  /// True when the server handed back a code, i.e. a dev-mode response.
  bool get hasDevOtp => (devOtp ?? '').isNotEmpty;

  factory ForgotPasswordResult.fromJson(Map<String, dynamic> json) {
    return ForgotPasswordResult(
      email: json['email']?.toString() ?? '',
      ttlMinutes: (json['ttlMinutes'] as num?)?.toInt() ?? 10,
      devOtp: json['devOtp']?.toString(),
    );
  }
}

/// Draft of the details collected on the Create Account screen before the
/// request is sent.
///
/// Kept as a small value object so the single register page can build its
/// payload in one place; it is no longer forwarded between two screens.
class RegistrationDraft {
  final String role;
  final String name;
  final String email;
  final String phone;

  /// Mandatory for owners, optional for vehicle users.
  final String? upiId;

  const RegistrationDraft({
    required this.role,
    required this.name,
    required this.email,
    required this.phone,
    this.upiId,
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'name': name,
    'email': email,
    'phone': phone,
    if ((upiId ?? '').isNotEmpty) 'upiId': upiId,
  };

  factory RegistrationDraft.fromJson(Map<String, dynamic> json) {
    final upi = (json['upiId']?.toString() ?? '').trim();
    return RegistrationDraft(
      role: json['role']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      upiId: upi.isEmpty ? null : upi,
    );
  }
}
