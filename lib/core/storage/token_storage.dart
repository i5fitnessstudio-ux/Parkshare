import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure local storage of auth tokens.
///
/// Android: encrypted SharedPreferences / Keystore.
/// iOS: Keychain.
class TokenStorage {
  static const _accessKey = 'parkshare_access_token';
  static const _refreshKey = 'parkshare_refresh_token';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<String?> getAccessToken() => _storage.read(key: _accessKey);

  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  Future<bool> hasTokens() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);
    return access != null && access.isNotEmpty && refresh != null;
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}
