import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/models/user.dart';

/// Caches the last authenticated session (user + role) in secure storage so
/// the splash screen can route instantly while the token is being validated.
class SessionStorage {
  static const _userKey = 'parkshare_session_user';
  static const _roleKey = 'parkshare_session_role';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveSession(User user) async {
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    await _storage.write(key: _roleKey, value: user.role);
  }

  Future<String?> getRole() => _storage.read(key: _roleKey);

  Future<User?> getUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _roleKey);
  }
}
