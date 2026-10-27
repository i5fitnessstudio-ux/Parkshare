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

/// Login screen. Used for both roles; `role` tints the visual system
/// (owner = green, user = blue) and is enforced by the backend.
class LoginScreen extends StatefulWidget {
  final Object? arguments;

  const LoginScreen({super.key, this.arguments});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  /// Passwords start HIDDEN; the eye in the field toggles them.
  bool _obscure = true;
  bool _loading = false;

  String? get _role {
    final a = widget.arguments;
    if (a is String) return a;
    if (a is Map) return a['role']?.toString();
    return null;
  }

  String? get _prefilledEmail {
    final a = widget.arguments;
    if (a is Map) return a['prefilledEmail']?.toString();
    return null;
  }

  String? get _successMessage {
    final a = widget.arguments;
    if (a is Map) return a['message']?.toString();
    return null;
  }

  bool get _isOwner => _role == 'owner';
  Color get _accent => _isOwner ? AppColors.ownerPrimary : AppColors.brandBlue;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: _prefilledEmail ?? '');
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    try {
      await auth.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: _role,
      );
      if (!mounted) return;
      final route = _isOwner ? AppRoutes.ownerDashboard : AppRoutes.userHome;
      Navigator.of(context).pushNamedAndRemoveUntil(route, (route) => false);
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

  void _goRegister() {
    Navigator.of(context).pushNamed(AppRoutes.register, arguments: _role);
  }

  // Password recovery is intentionally not offered on the login screen: the
  // owner and vehicle-user login forms only accept an admin-issued account, so
  // a public "Forgot password?" link led to a dead end. The flow itself is
  // untouched and still reachable at AppRoutes.forgotPassword.

  @override
  Widget build(BuildContext context) {
    final title = _isOwner
        ? '${AppStrings.roleOwnerTitle} ${AppStrings.login}'
        : '${AppStrings.roleUserTitle} ${AppStrings.login}';

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
                      height: 40,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    AppStrings.loginSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (_successMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            size: 18,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  CustomTextField(
                    controller: _emailController,
                    label: AppStrings.email,
                    hint: AppStrings.emailHint,
                    prefixIcon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 20),
                  CustomTextField(
                    controller: _passwordController,
                    label: AppStrings.password,
                    hint: AppStrings.passwordHint,
                    prefixIcon: Icons.lock_outline,
                    obscure: _obscure,
                    suffixIcon: _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    suffixTooltip: _obscure ? 'Show password' : 'Hide password',
                    onSuffixTap: () => setState(() => _obscure = !_obscure),
                    textInputAction: TextInputAction.done,
                    validator: Validators.password,
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    label: AppStrings.login,
                    loading: _loading,
                    icon: Icons.login,
                    backgroundColor: _accent,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 24),
                  // Wrap instead of Row: at larger system text scales the "New
                  // here?" line must flow onto a second line, never overflow.
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          AppStrings.newHere,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _goRegister,
                        child: Text(
                          AppStrings.createAccount,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                      ),
                    ],
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
