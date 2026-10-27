import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/dev_flags.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';
import '../providers/auth_provider.dart';

/// Forgot password: enter email -> OTP sent -> OTP verification screen.
///
/// SECURITY (audit H-03): the message shown after a successful request is the
/// backend's single shared wording, so a registered and an unregistered address
/// are indistinguishable.
///
/// SECURITY (audit H-02): in development the backend may echo the OTP back as
/// `devOtp` (only when `ALLOW_DEV_OTP=true` and no SMTP is configured). It is
/// forwarded here only when [DevFlags.devOtpEnabled] — a debug build with the
/// flag set — so a release binary never carries it into the next route even if
/// the payload contained one.
class ForgotPasswordScreen extends StatefulWidget {
  final Map<String, dynamic>? arguments;

  const ForgotPasswordScreen(this.arguments, {super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _loading = false;

  String? get _role => widget.arguments?['role']?.toString();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    try {
      final result = await auth.forgotPassword(_emailController.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushNamed(
        AppRoutes.otpVerification,
        arguments: {
          'email': result.email,
          // Audit H-02: dropped entirely unless this build opted in.
          if (DevFlags.devOtpEnabled) 'devOtp': result.devOtp,
          'role': _role,
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
                      Icons.lock_reset,
                      size: 36,
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    AppStrings.forgotPasswordTitle,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    AppStrings.forgotPasswordSubtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  CustomTextField(
                    controller: _emailController,
                    label: AppStrings.email,
                    hint: AppStrings.emailHint,
                    prefixIcon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    validator: Validators.email,
                    onSubmitted: () => _sendOtp(),
                  ),
                  const SizedBox(height: 32),
                  PrimaryButton(
                    label: AppStrings.sendOtp,
                    loading: _loading,
                    icon: Icons.send,
                    onPressed: _sendOtp,
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
