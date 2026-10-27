import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';
import '../../../shared/widgets/terms_consent_checkbox.dart';
import '../providers/auth_provider.dart';

/// Create Account — Signup screen updated with Image 6 UI layout & styling.
class RegisterScreen extends StatefulWidget {
  final String? role;

  const RegisterScreen({super.key, this.role});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _upiController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _loading = false;

  /// Mandatory legal consent. The Continue button stays disabled until this is
  /// true, so an account can never be created without agreeing to the
  /// Terms & Conditions and the Privacy Policy.
  bool _acceptedTerms = false;

  /// Shown once, under the consent row, after a blocked submit attempt.
  String? _termsError;

  bool get _isOwner => widget.role == UserRole.owner;
  Color get _accent => _isOwner ? AppColors.ownerPrimary : AppColors.brandBlue;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _upiController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Creates the account, but only once every field is valid AND the legal
  /// consent box is ticked. The consent is checked FIRST so an unchecked box
  /// is reported even when the form is also invalid, which is the message the
  /// user needs to see first.
  Future<void> _submit() async {
    if (_loading) return;

    if (!_acceptedTerms) {
      setState(() {
        _termsError = AppStrings.consentRequired;
        _loading = false;
      });
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _termsError = null);
      return;
    }
    setState(() => _termsError = null);

    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final role = widget.role ?? UserRole.user;
    try {
      await auth.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        upiId: _upiController.text.trim(),
        password: _passwordController.text,
        role: role,
      );
      if (!mounted) return;
      showSnack(context, 'Account created successfully.');
      final route = _isOwner ? AppRoutes.ownerDashboard : AppRoutes.userHome;
      Navigator.of(context).pushNamedAndRemoveUntil(route, (route) => false);
    } on ApiException catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, isError: true);
      if (e.isAuthError) {
        Navigator.of(context)
            .pushReplacementNamed(AppRoutes.login, arguments: role);
      }
    } catch (_) {
      if (!mounted) return;
      showSnack(context, AppStrings.errorGeneric, isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildStepIndicator(int currentStep) {
    final steps = [
      'Personal Details',
      'Vehicle Details',
      'Preferences',
      'Photos',
    ];
    return Row(
      children: List.generate(steps.length, (i) {
        final stepNum = i + 1;
        final isActive = stepNum == currentStep;
        final isDone = stepNum < currentStep;
        final color = (isActive || isDone) ? _accent : Colors.grey.shade300;
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i == 0
                          ? Colors.transparent
                          : (isDone ? _accent : Colors.grey.shade300),
                    ),
                  ),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isActive || isDone) ? _accent : Colors.white,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '$stepNum',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: (isActive || isDone)
                              ? Colors.white
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i == steps.length - 1
                          ? Colors.transparent
                          : (isDone ? _accent : Colors.grey.shade300),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                steps[i],
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? _accent : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Form(
            key: _formKey,
            child: ConstrainedContent(
              maxWidth: ResponsiveLayout.formMaxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/parkshare/logo.png',
                      height: 38,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Create Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Let's get you ready to park smarter",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildStepIndicator(1),
                  const SizedBox(height: 24),

                  // ---- Identity Fields ----
                  CustomTextField(
                    controller: _nameController,
                    label: 'Full Name',
                    hint: 'Enter your name',
                    prefixIcon: Icons.person_outline,
                    textInputAction: TextInputAction.next,
                    enabled: !_loading,
                    validator: Validators.name,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _phoneController,
                    label: 'Mobile Number',
                    hint: 'Enter your mobile number',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    enabled: !_loading,
                    validator: Validators.phone,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _emailController,
                    label: 'Email Address',
                    hint: 'Enter your email address',
                    prefixIcon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    enabled: !_loading,
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 16),

                  // ---- UPI ID (optional for all) ----
                  CustomTextField(
                    controller: _upiController,
                    label: AppStrings.upiId,
                    hint: AppStrings.upiIdHint,
                    helper: AppStrings.upiIdUserHint,
                    helperStyle: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                    ),
                    prefixIcon: Icons.account_balance_wallet_outlined,
                    textInputAction: TextInputAction.next,
                    enabled: !_loading,
                    validator: (value) => Validators.upiId(value, required: false),
                  ),
                  const SizedBox(height: 16),

                  // ---- Password ----
                  CustomTextField(
                    controller: _passwordController,
                    label: AppStrings.password,
                    hint: AppStrings.passwordHint,
                    prefixIcon: Icons.lock_outline,
                    obscure: _obscure,
                    textInputAction: TextInputAction.next,
                    enabled: !_loading,
                    validator: Validators.password,
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _confirmController,
                    label: AppStrings.confirmPassword,
                    hint: 'Re-enter your password',
                    prefixIcon: Icons.lock_outline,
                    obscure: _obscure,
                    textInputAction: TextInputAction.done,
                    enabled: !_loading,
                    validator: (value) => Validators.confirmPassword(
                      value,
                      _passwordController.text,
                    ),
                    onSubmitted: () => _submit(),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Checkbox(
                        value: !_obscure,
                        onChanged: _loading
                            ? null
                            : (v) => setState(() => _obscure = !(v ?? true)),
                        activeColor: _accent,
                      ),
                      const Text(
                        AppStrings.showPassword,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ---- Mandatory legal consent (green for owners, blue for
                  // vehicle users) ----
                  TermsConsentCheckbox(
                    value: _acceptedTerms,
                    enabled: !_loading,
                    accent: _accent,
                    errorText: _termsError,
                    onChanged: (v) => setState(() {
                      _acceptedTerms = v;
                      // Clearing the box clears its error too, so the message
                      // never lingers after the user has fixed it.
                      _termsError = v ? null : _termsError;
                    }),
                  ),
                  const SizedBox(height: 20),

                  // Disabled until the consent box is ticked.
                  PrimaryButton(
                    label: 'Continue',
                    loading: _loading,
                    backgroundColor: _accent,
                    onPressed: (_loading || !_acceptedTerms) ? null : _submit,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
