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

/// OTP verification: 6-digit code with auto-advance, resend support.
class OtpVerificationScreen extends StatefulWidget {
  final Map<String, dynamic>? arguments;

  const OtpVerificationScreen(this.arguments, {super.key});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _boxes = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  bool _sending = false;

  String get _email => widget.arguments?['email']?.toString() ?? '';

  /// The OTP the backend echoed back — development builds only.
  ///
  /// SECURITY (audit H-02): this is gated on [DevFlags.devOtpEnabled], which is
  /// false unless the build is a debug build *and* `ALLOW_DEV_OTP=true` was
  /// passed explicitly. The raw argument is never read directly, so a release
  /// binary cannot render or pre-fill a code even if a server (or a MITM, or a
  /// cached response) puts one in the payload.
  String? get _devOtp {
    if (!DevFlags.devOtpEnabled) return null;
    return widget.arguments?['devOtp']?.toString();
  }

  String? get _role => widget.arguments?['role']?.toString();

  String get _otp => _boxes.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    // Pre-fill the OTP in dev builds so the flow is testable.
    final otp = _devOtp;
    if (otp != null && otp.length == 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (var i = 0; i < 6; i++) {
          _boxes[i].text = otp[i];
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _boxes) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(int index, String value) {
    if (value.length > 1) {
      // Paste support: fill all boxes.
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < 6 && i < digits.length; i++) {
        _boxes[i].text = digits[i];
      }
      _focusNodes[digits.length >= 6 ? 5 : digits.length].requestFocus();
      return;
    }
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  Future<void> _verify() async {
    if (_otp.length != 6) {
      showSnack(context, 'Please enter the 6-digit code.', isError: true);
      return;
    }
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    try {
      await auth.verifyResetOtp(_email, _otp);
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.resetPassword,
        arguments: {'email': _email, 'otp': _otp, 'role': _role},
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

  Future<void> _resend() async {
    setState(() => _sending = true);
    final auth = context.read<AuthProvider>();
    try {
      await auth.forgotPassword(_email);
      if (!mounted) return;
      showSnack(context, 'A new OTP has been sent to your email.');
    } on ApiException catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, isError: true);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                    Icons.verified_user,
                    size: 36,
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  AppStrings.otpTitle,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${AppStrings.otpSubtitle}\n$_email',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_devOtp != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      // Audit H-02: only reachable when DevFlags.devOtpEnabled,
                      // i.e. a debug build with ALLOW_DEV_OTP=true.
                      'Development mode: OTP auto-filled ($_devOtp)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Row(
                  children: List.generate(6, (i) {
                    // Expanded + max 52 dp wide: the six boxes share the row
                    // evenly on small screens (no fixed 48 dp overflow risk) and
                    // stay snug on tablets instead of stretching to fill.
                    return Expanded(
                      child: Center(
                        child: SizedBox(
                          width: 52,
                          height: 64,
                          child: CustomTextField(
                            controller: _boxes[i],
                            label: '',
                            validator: null,
                            onChanged: (v) => _onChanged(i, v),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: AppStrings.verify,
                  loading: _loading,
                  icon: Icons.check_circle_outline,
                  onPressed: _verify,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _sending ? null : _resend,
                  child: Text(
                    _sending ? 'Sending…' : AppStrings.resendOtp,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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
