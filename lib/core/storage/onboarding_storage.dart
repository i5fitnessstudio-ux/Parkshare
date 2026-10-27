import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tracks whether onboarding has been completed.
class OnboardingStorage {
  static const _onboardingCompletedKey = 'parkshare_onboarding_completed';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> setOnboardingCompleted(bool completed) async {
    await _storage.write(
      key: _onboardingCompletedKey,
      value: completed ? 'true' : 'false',
    );
  }

  Future<bool> hasOnboardingCompleted() async {
    final value = await _storage.read(key: _onboardingCompletedKey);
    return value == 'true';
  }

  Future<void> clear() async {
    await _storage.delete(key: _onboardingCompletedKey);
  }
}
