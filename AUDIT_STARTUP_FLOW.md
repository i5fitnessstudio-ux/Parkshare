# ParkShare — Startup / Onboarding / Role-Selection Flow

Scope: startup navigation only. No backend, database, payment, booking, map,
vehicle, owner/user dashboard, location, or API-contract changes.

## Required flow (now deterministic on every cold start)

```
Native Android splash
  -> BlueSplashScreen   (1.5 s, blue, no white logo page)
  -> SplashScreen       (the single startup decision point, same blue)
  -> OnboardingIntroScreen  page 1 "Find Nearby Parking"
                            page 2 "Book Instantly"
                            page 3 "Earn with Your Space"
  -> RoleSelectionNewScreen  "Select Who You Are"
        User  -> Vehicle User Login   (existing)
        Owner -> Parking Owner Login  (existing)
```

`Next` on page 3 and `Skip` both go to **Role Selection** — never a login or a
dashboard directly.

## Root cause (why onboarding / role selection were sometimes skipped)

`lib/modules/splash/splash_screen.dart` used to `await auth.restoreSession()`
and then choose the startup route from the result plus a persisted flag:

- authenticated  -> `ownerDashboard` / `userHome` (bypassed onboarding **and**
  role selection),
- unauthenticated **and** `OnboardingStorage.hasOnboardingCompleted()` ->
  `roleSelection` (bypassed onboarding).

`lib/modules/onboarding/onboarding_intro_screen.dart` wrote that flag
(`setOnboardingCompleted(true)`) when the last page was completed. So after the
first run, onboarding never appeared again; and any restored session jumped
straight to a dashboard. There was also no `Skip` button on the active
onboarding screen (the `Skip`-bearing `OnboardingScreen` is unused dead code).

## Fix

- `SplashScreen` no longer reads the session or the onboarding flag. Its
  `initState` post-frame callback makes one decision: `pushReplacementNamed`
  to `AppRoutes.onboarding`. Stored tokens are **not** cleared — they are
  simply not allowed to choose the startup route.
- `OnboardingIntroScreen`: removed the `OnboardingStorage` write; added a
  visible `Skip` that calls the same exit as the last-page `Next`
  (`pushReplacementNamed(AppRoutes.roleSelection)`); added a `PopScope` so
  Android back goes page 3 -> 2 -> 1.
- `RoleSelectionNewScreen` is unchanged (it already routes to the existing
  role login via `pushNamed`).

## Race conditions removed

- No `await` of `restoreSession()` exists in the startup path any more, so a
  late session restore can never `pushReplacement` a dashboard over onboarding.
- Only `SplashScreen` navigates during startup; `BlueSplashScreen` only does
  the timed hand-off to it.
- `pushReplacement` is used for splash -> onboarding -> role selection, so the
  back stack never contains a temporary splash/onboarding screen under role
  selection.

## Session handling

Tokens/session are preserved (never deleted here). The startup route is
intentionally independent of them: even a device with a stored session goes
Splash -> Onboarding -> Role Selection -> role login, as requested. Session
restoration is no longer invoked during startup.

## Verification

- `flutter analyze` -> No issues found.
- `flutter test` -> all tests pass, including new `test/widget_test.dart`:
  cold-boot onboarding, Next x3 -> Role Selection, Skip -> Role Selection, and
  "a stored session does NOT bypass onboarding".
- Emulator (Pixel Tablet, Android 15): cold start shows page 1
  "Find Nearby Parking"; Next -> "Book Instantly" -> "Earn with Your Space" ->
  "Select Who You Are"; User -> "Vehicle User Login"; Owner -> "Parking Owner
  Login"; Skip -> "Select Who You Are"; full force-stop + relaunch shows
  onboarding again. Verified at tablet landscape, tablet portrait (800x1280 dp)
  and phone portrait (1080x2400 @ 440 dpi) with no `RenderFlex overflowed`
  errors in logcat.
