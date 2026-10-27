import 'package:flutter/material.dart';

import '../../app/routes.dart';

/// Startup/bootstrap screen — the ONE place that decides where a cold start
/// goes.
///
/// It runs directly after `BlueSplashScreen` and keeps the SAME blue
/// background, so the blue splash visually continues while the app starts and
/// there is no separate white logo page.
///
/// STARTUP RULE (intentional): the app always opens the onboarding carousel
/// first, then the role-selection screen, then the role's login flow. This is
/// deliberately independent of any stored session:
///
///   * no session restore is awaited here any more — it used to finish first
///     and `pushReplacement` straight to the owner/user dashboard, which is
///     exactly why onboarding and role selection were skipped on some launches;
///   * no `onboardingCompleted` flag is consulted — onboarding is shown on
///     every cold start;
///   * stored tokens are NOT cleared; they are simply not allowed to choose
///     the startup route (see `AUDIT_STARTUP_FLOW.md`).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // The single deterministic startup decision. `pushReplacement` means the
    // splash is removed from the stack, so the back button can never return to
    // a temporary startup screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.onboarding);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Identical blue to `BlueSplashScreen`, so the hand-off is seamless.
    return const Scaffold(
      backgroundColor: Color(0xFF155EC8),
      body: SizedBox.expand(),
    );
  }
}
