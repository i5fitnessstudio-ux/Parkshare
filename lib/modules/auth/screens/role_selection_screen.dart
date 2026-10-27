import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Role selection: Parking Owner (green) vs Vehicle User (blue).
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  void _pickRole(BuildContext context, String role) {
    Navigator.of(context).pushNamed(AppRoutes.login, arguments: role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appName)),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedContent(
            maxWidth: ResponsiveLayout.formMaxWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  const Text(
                    AppStrings.chooseYourRole,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 40),
                  _RoleCard(
                    title: AppStrings.roleOwnerTitle,
                    subtitle: AppStrings.roleOwnerSubtitle,
                    icon: Icons.garage,
                    color: AppColors.ownerPrimary,
                    lightColor: AppColors.ownerPrimaryLight,
                    onTap: () => _pickRole(context, 'owner'),
                  ),
                  const SizedBox(height: 20),
                  _RoleCard(
                    title: AppStrings.roleUserTitle,
                    subtitle: AppStrings.roleUserSubtitle,
                    icon: Icons.directions_car,
                    color: AppColors.userPrimary,
                    lightColor: AppColors.userPrimaryLight,
                    onTap: () => _pickRole(context, 'user'),
                  ),
                  const SizedBox(height: 32),
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
