# Asset Mapping - ParkShare

## Google Drive Reference
All required ParkShare images are from: https://drive.google.com/drive/folders/1zp6Ty3I6z6cNQzbltQs1v0OdNF5E0j8J?usp=sharing

## Local Asset Paths

| Asset | Local Path | Purpose |
|---|---|---|
| ParkShare Logo | assets/images/parkshare/logo.png | Screen 2 - White Logo Page, Auth screens |
| Find Nearby Parking | assets/images/parkshare/onboarding/find_nearby.png | Screen 3 - Onboarding page 1 |
| Book Instantly | assets/images/parkshare/onboarding/book_instantly.png | Screen 4 - Onboarding page 2 |
| Earn With Your Space | assets/images/parkshare/onboarding/earn_space.png | Screen 5 - Onboarding page 3 |
| Role Select | assets/images/parkshare/onboarding/role_select.png | Screen 6 - Role selection illustration |

## Usage Notes
- All onboarding images use BoxFit.contain with responsive sizing (~40% of screen width)
- No Google Drive URLs used directly in Flutter code
- Existing technical parking diagram (parking_dimensions.png) removed from onboarding UI
- Assets must be downloaded from Drive folder if not present locally

## Files Modified
- lib/modules/onboarding/blue_splash_screen.dart
- lib/modules/onboarding/onboarding_logo_screen.dart
- lib/modules/onboarding/onboarding_intro_screen.dart
- lib/modules/auth/screens/role_selection_new_screen.dart
- lib/app/app.dart, lib/app/routes.dart
- lib/core/constants/app_colors.dart
- lib/core/storage/onboarding_storage.dart, dev_reset_helper.dart
- lib/modules/auth/providers/auth_provider.dart

## Startup Flow
1. Blue Splash (#1F5EBB) - 1.5s
2. White Logo Screen - 1.2s  
3. Find Nearby Parking
4. Book Instantly
5. Earn With Your Space
6. Select Who You Are (User/Owner)
7. Login/Create Account per role

## Clear App Data (Development)
Package name: com.example.parkshare_new

Android (ADB):
```bash
adb shell pm clear com.example.parkshare_new
```

Flutter clean reinstall:
```bash
flutter clean
flutter install
```

Run on Pixel 9 emulator:
```bash
flutter run -d pixel_9
```
