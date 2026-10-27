import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/responsive/responsive_layout.dart';

/// The 3-page onboarding carousel (existing design/assets, unchanged).
///
/// STARTUP RULE: this is the first interactive screen of every cold start.
/// Both "Next" on the last page and "Skip" go to the SAME place — the existing
/// role-selection screen. It is never allowed to branch to a dashboard/login
/// based on a stored session, and it no longer writes an `onboardingCompleted`
/// flag (that flag was what made later launches skip onboarding entirely).
class OnboardingIntroScreen extends StatefulWidget {
  const OnboardingIntroScreen({super.key});

  @override
  State<OnboardingIntroScreen> createState() => _OnboardingIntroScreenState();
}

class _OnboardingIntroScreenState extends State<OnboardingIntroScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      title: 'Find Nearby Parking',
      body: 'Find safe and affordable parking\nspace near you in seconds',
      color: AppColors.brandBlue,
      imageAsset: 'assets/images/parkshare/onboarding/find_nearby.png',
    ),
    (
      title: 'Book Instantly',
      body: 'Book your parking slot\ninstantly and hassle free',
      color: AppColors.brandBlue,
      imageAsset: 'assets/images/parkshare/onboarding/book_instantly.png',
    ),
    (
      title: 'Earn with Your Space',
      body: 'List your empty parking\nand start earning easily',
      color: AppColors.brandBlue,
      imageAsset: 'assets/images/parkshare/onboarding/earn_space.png',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The single exit of onboarding: always the existing role-selection screen.
  /// No session inspection, no dashboard, no login shortcut.
  void _goToRoleSelection() {
    Navigator.of(context).pushReplacementNamed(AppRoutes.roleSelection);
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    } else {
      _goToRoleSelection();
    }
  }

  /// Android back: page 3 -> page 2 -> page 1. On page 1 the default system
  /// behaviour (leave the app) is preserved via `canPop`.
  void _previous() {
    if (_page > 0 && _controller.hasClients) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _previous();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: ConstrainedContent(
            maxWidth: ResponsiveLayout.formMaxWidth,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: TextButton(
                      onPressed: _goToRoleSelection,
                      child: const Text(
                        AppStrings.skip,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) {
                      final p = _pages[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 8),
                            Text(
                              p.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: p.color,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              p.body,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Expanded(
                              child: Center(
                                child: Image.asset(
                                  p.imageAsset,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pages.length, (i) {
                    final active = i == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active ? AppColors.brandBlue : AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                  child: PrimaryButton(
                    label: AppStrings.next,
                    onPressed: _next,
                    backgroundColor: AppColors.brandBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
