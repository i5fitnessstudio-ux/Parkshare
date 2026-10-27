import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';
import '../../auth/providers/auth_provider.dart';

/// Step two of self-service account deletion.
///
/// The first step (the "Delete Account?" dialog) happens on the home screen;
/// this screen re-authenticates the user with their password before the account
/// is deleted. A wrong password is a 403 (authorization), never a 401, so the
/// app must not treat it as an expired session — the message is mapped locally
/// instead of through [ErrorMessages].
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const String _successMessage =
      'Your ParkShare account has been deleted successfully.';
  static const String _wrongPasswordMessage =
      'Incorrect password. Please try again.';
  static const String _unreachableMessage =
      'Unable to connect to the server. Please try again.';
  static const String _genericMessage =
      'Unable to delete your account right now. Please try again.';

  final TextEditingController _passwordController = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;

  /// Set to true right before we pop after the user confirmed they want to
  /// leave; until then Android back is intercepted.
  bool _allowPop = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting && _passwordController.text.trim().isNotEmpty;

  /// Maps a failure to spec-exact copy. Never surfaces an exception message.
  String _messageForError(Object error) {
    if (error is ApiException) {
      switch (error.type) {
        case ApiErrorType.authorization:
          return _wrongPasswordMessage;
        case ApiErrorType.network:
          return _unreachableMessage;
        default:
          return _genericMessage;
      }
    }
    return _genericMessage;
  }

  Future<void> _delete() async {
    if (_submitting) return;
    final password = _passwordController.text;
    if (password.trim().isEmpty) return;

    setState(() => _submitting = true);
    final auth = context.read<AuthProvider>();
    try {
      await auth.deleteAccount(password);
      if (!mounted) return;
      // Stop the spinner before the modal success dialog: the barrier blocks
      // further taps, and a lingering progress indicator would keep the frame
      // scheduler busy behind it.
      setState(() => _submitting = false);
      await _showSuccessDialog();
      if (!mounted) return;
      // Clear the whole stack so back cannot return to an authenticated screen.
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.roleSelection,
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      showSnack(context, _messageForError(error), isError: true);
      setState(() => _submitting = false);
    }
  }

  Future<void> _showSuccessDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_outline,
          color: AppColors.success,
          size: 40,
        ),
        title: const Text('Account deleted'),
        content: const Text(_successMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel account deletion?'),
        content: const Text(
          'Your account will not be deleted and will remain active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (!mounted || !leave) return;
        setState(() => _allowPop = true);
        // Wait for the rebuild so `canPop` is true, then leave.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Delete Account')),
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
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      size: 36,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Delete your account permanently',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This will permanently remove your account and cannot be '
                    'undone. Enter your password to confirm.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  CustomTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    prefixIcon: Icons.lock_outline,
                    obscure: _obscure,
                    enabled: !_submitting,
                    suffixIcon: _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    suffixTooltip: _obscure ? 'Show password' : 'Hide password',
                    onSuffixTap: () => setState(() => _obscure = !_obscure),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: () => _delete(),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Delete Account Permanently',
                    icon: Icons.delete_forever,
                    loading: _submitting,
                    backgroundColor: AppColors.error,
                    disabledBackgroundColor:
                        AppColors.error.withValues(alpha: 0.4),
                    onPressed: _canSubmit ? _delete : null,
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
