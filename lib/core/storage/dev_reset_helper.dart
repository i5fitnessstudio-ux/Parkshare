import 'package:flutter/foundation.dart';

import '../constants/app_identity.dart';
import 'onboarding_storage.dart';
import 'token_storage.dart';

/// Development helper to reset app state for testing onboarding flow.
/// This should not be exposed in production UI.
class DevResetHelper {
  static Future<void> resetForTesting() async {
    if (!kDebugMode) return;
    final tokenStorage = TokenStorage();
    final onboardingStorage = OnboardingStorage();
    await tokenStorage.clear();
    await onboardingStorage.clear();
  }

  static String getInstructions() {
    return '''For testing the onboarding flow when tokens are stored:

Development options:
1. Use flutter clean and uninstall app:
   flutter clean
   flutter install (or uninstall+install from IDE)

2. Use ADB to clear package (Android):
   adb shell pm clear ${AppIdentity.androidPackageName}

Note: ${AppIdentity.androidPackageName} is applicationId from
android/app/build.gradle.kts (single source: AppIdentity).

The reset helper is only available in debug mode for programmatic clearing.''';
  }
}
