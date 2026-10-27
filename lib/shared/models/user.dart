/// Roles supported by ParkShare.
class UserRole {
  UserRole._();

  static const String owner = 'owner';
  static const String user = 'user';

  static bool isValid(String? role) => role == owner || role == user;
}

/// Authenticated user.
class User {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final bool isActive;
  final DateTime createdAt;

  /// The user's own UPI virtual payment address.
  ///
  /// Mandatory for parking **owners** (it is where users pay them) and optional
  /// for vehicle users (they mostly pay by UPI to someone else).
  final String? upiId;

  const User({
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

  /// True when a usable UPI address is on record.
  bool get hasUpiId => (upiId ?? '').isNotEmpty;

  factory User.fromJson(Map<String, dynamic> json) {
    final upi = (json['upiId']?.toString() ?? '').trim().toLowerCase();
    return User(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      role: json['role']?.toString() ?? '',
      isActive: json['isActive'] == true,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      upiId: upi.isEmpty ? null : upi,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'phone': phone,
    'role': role,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
    'upiId': upiId,
  };
}
