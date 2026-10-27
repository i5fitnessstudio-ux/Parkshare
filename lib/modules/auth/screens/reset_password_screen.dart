import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';
import '../providers/auth_provider.dart';

/// Reset password: new password + confirm, then back to Login.
class ResetPasswordScreen extends StatefulWidget {
  final Map<String, dynamic>? arguments;

  const ResetPasswordScreen(this.arguments, {super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  String get _email => widget.arguments?['email']?.toString() ?? '';
  String get _otp => widget.arguments?['otp']?.toString() ?? '';
  String? get _role => widget.arguments?['role']?.toString();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    try {
      await auth.resetPassword(
        email: _email,
        otp: _otp,
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      // Back to login with a pre-filled email + success banner.
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.login,
        (route) => false,
        arguments: {
          'role': _role,
          'prefilledEmail': _email,
          'message': 'Password reset successful. Please log in.',
        },
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showSnack(context, AppStrings.errorGeneric, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: ConstrainedContent(
              maxWidth: ResponsiveLayout.formMaxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.password,
                      size: 36,
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    AppStrings.resetPasswordTitle,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    AppStrings.resetPasswordSubtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  CustomTextField(
                    controller: _passwordController,
                    label: AppStrings.password,
                    hint: 'New password (min 6 chars)',
                    prefixIcon: Icons.lock_outline,
                    obscure: _obscure,
                    textInputAction: TextInputAction.next,
                    validator: Validators.password,
                  ),
                  const SizedBox(height: 20),
                  CustomTextField(
                    controller: _confirmController,
                    label: AppStrings.confirmPassword,
                    hint: 'Re-enter new password',
                    prefixIcon: Icons.lock_outline,
                    obscure: _obscure,
                    textInputAction: TextInputAction.done,
                    validator: (value) => Validators.confirmPassword(
                      value,
                      _passwordController.text,
                    ),
                    onSubmitted: () => _submit(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: !_obscure,
                        onChanged: (v) =>
                            setState(() => _obscure = !(v ?? true)),
                        activeColor: AppColors.info,
                      ),
                      const Text(
                        'Show password',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: AppStrings.submit,
                    loading: _loading,
                    icon: Icons.done_all,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
