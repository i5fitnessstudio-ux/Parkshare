import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/responsive/responsive_layout.dart';

/// Onboarding carousel (3 pages, Figma-style), then -> Role Selection.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      icon: Icons.local_parking,
      color: AppColors.ownerPrimary,
      title: AppStrings.onboardTitle1,
      body: AppStrings.onboardBody1,
    ),
    (
      icon: Icons.checklist_rtl,
      color: AppColors.userPrimary,
      title: AppStrings.onboardTitle2,
      body: AppStrings.onboardBody2,
    ),
    (
      icon: Icons.attach_money,
      color: AppColors.info,
      title: AppStrings.onboardTitle3,
      body: AppStrings.onboardBody3,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    } else {
      Navigator.of(context).pushReplacementNamed(AppRoutes.roleSelection);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ConstrainedContent(
          maxWidth: ResponsiveLayout.formMaxWidth,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context)
                          .pushReplacementNamed(AppRoutes.roleSelection),
                  child: const Text(AppStrings.skip),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final p = _pages[i];
                    // Centred when it fits; scrolls vertically on short screens
                    // (small phones, large system text) instead of overflowing.
                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                color: p.color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(32),
                              ),
                              child: Icon(p.icon, size: 72, color: p.color),
                            ),
                            const SizedBox(height: 40),
                            Text(
                              p.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              p.body,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
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
                    width: active ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? AppColors.brand : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                child: PrimaryButton(
                  label: isLast ? AppStrings.getStarted : AppStrings.next,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
