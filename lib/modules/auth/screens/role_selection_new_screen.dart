import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Role selection screen with the specified design.
class RoleSelectionNewScreen extends StatelessWidget {
  const RoleSelectionNewScreen({super.key});

  void _pickRole(BuildContext context, String role) {
    Navigator.of(context).pushNamed(AppRoutes.login, arguments: role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedContent(
              maxWidth: ResponsiveLayout.formMaxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  const Text(
                    'Find • Book • Park',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Share Your Space. Save Your Time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Image.asset(
                    'assets/images/parkshare/onboarding/find_nearby.png',
                    height: 140,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Select Who You Are',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose an option to continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _RoleCard(
                    title: 'User',
                    subtitle: 'Find and book parking\nspace near you.',
                    icon: Icons.person,
                    color: AppColors.brandBlue,
                    lightColor: AppColors.userPrimaryLight,
                    onTap: () => _pickRole(context, 'user'),
                  ),
                  const SizedBox(height: 20),
                  _RoleCard(
                    title: 'Owner',
                    subtitle: 'List your parking space\nand start earning.',
                    icon: Icons.garage,
                    color: AppColors.ownerPrimary,
                    lightColor: AppColors.ownerPrimaryLight,
                    onTap: () => _pickRole(context, 'owner'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color lightColor;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.lightColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: lightColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
