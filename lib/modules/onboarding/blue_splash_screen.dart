import 'package:flutter/material.dart';

import '../../app/routes.dart';

/// First splash screen with blue background.
///
/// Purely a launch frame: it holds the blue ParkShare splash while the app
/// starts, then hands over directly to the session bootstrap
/// (`AppRoutes.splash`, SplashScreen), which restores the session and routes
/// to the right screen. There is intentionally NO white logo screen in
/// between.
class BlueSplashScreen extends StatefulWidget {
  const BlueSplashScreen({super.key});

  @override
  State<BlueSplashScreen> createState() => _BlueSplashScreenState();
}

class _BlueSplashScreenState extends State<BlueSplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.splash);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF155EC8),
      body: SizedBox.expand(),
    );
  }
}
