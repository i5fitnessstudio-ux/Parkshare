/// User roles.
class UserRole {
  UserRole._();
  static const String owner = 'owner';
  static const String user = 'user';

  /// Back-office role for settlement operations only. Never created by the
  /// public registration endpoint — an operator promotes/creates admins
  /// out-of-band (see migration 010).
  static const String admin = 'admin';

  /// Roles a caller may self-register as. Deliberately EXCLUDES [admin], so
  /// `POST /api/auth/register` can never mint an administrator.
  static const Set<String> all = {owner, user};

  /// Every role the database may hold.
  static const Set<String> every = {owner, user, admin};
}

/// Authenticated user representation.
class User {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String role; // 'user' | 'owner'
  final bool isActive;
  final DateTime createdAt;

  /// UPI virtual payment address this account receives money on.
  /// Mandatory for parking owners (their own UPI is the payment destination),
  /// optional for vehicle users. Null means "not configured yet".
  final String? upiId;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.isActive,
    required this.createdAt,
    this.upiId,
  });

  bool get isOwner => role == UserRole.owner;
  bool get isVehicleUser => role == UserRole.user;

  /// True when this account can be used as a UPI payee.
  bool get hasUpiId => (upiId ?? '').trim().isNotEmpty;

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'].toString(),
      name: map['name'] as String,
      email: map['email'] as String,
      phone: map['phone'] as String?,
      role: map['role'] as String,
      isActive: map['is_active'] == true || map['is_active'] == 't',
      createdAt: map['created_at'] is DateTime
          ? map['created_at'] as DateTime
          : DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now(),
      upiId: map['upi_id']?.toString().trim().isEmpty ?? true
          ? null
          : map['upi_id'].toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'phone': phone,
    'role': role,
    'isActive': isActive,
    'upiId': upiId,
    'hasUpiId': hasUpiId,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// Token pair returned by register/login/refresh.
class TokenPair {
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });
}

/// Combined auth payload returned by register/login/refresh.
class AuthPayload {
  final User user;
  final TokenPair tokens;

  AuthPayload({required this.user, required this.tokens});

  Map<String, dynamic> toJson() => {
    'user': user.toJson(),
    'accessToken': tokens.accessToken,
    'refreshToken': tokens.refreshToken,
    'accessExpiresAt': tokens.accessExpiresAt.toIso8601String(),
    'refreshExpiresAt': tokens.refreshExpiresAt.toIso8601String(),
  };
}
