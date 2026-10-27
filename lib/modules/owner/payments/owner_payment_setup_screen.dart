import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/error_messages.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/owner/providers/owner_payments_provider.dart';
import '../../../shared/models/owner_payment_info.dart';
import '../../../shared/utils/owner_payment_validation.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Owner "Set Up Payment Account" form.
///
/// Collects the legal/account-holder identity and bank details needed to
/// receive ParkShare settlements. The full account number and IFSC are sent
/// once to the backend, which stores only the last four digits — nothing here
/// is written to device storage.
///
/// Security: the owner id is never entered or sent. The backend derives it from
/// the JWT, so this screen can only ever edit the signed-in owner's setup.
class OwnerPaymentSetupScreen extends StatefulWidget {
  const OwnerPaymentSetupScreen({super.key});

  @override
  State<OwnerPaymentSetupScreen> createState() =>
      _OwnerPaymentSetupScreenState();
}

class _OwnerPaymentSetupScreenState extends State<OwnerPaymentSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _legalName = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _holder = TextEditingController();
  final _accountNumber = TextEditingController();
  final _confirmAccountNumber = TextEditingController();
  final _ifsc = TextEditingController();

  String _accountType = OwnerPaymentValidation.accountTypes.first;
  bool _consent = false;
  bool _consentError = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    // Re-loading an existing (masked) account cannot refill the full number, so
    // only identity/contact fields are prefilled for an update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _prefilled) return;
      _prefilled = true;
      final auth = context.read<AuthProvider>();
      final user = auth.user;
      if (user != null) {
        _email.text = user.email;
        _mobile.text = user.phone ?? '';
      }
      final account = context.read<OwnerPaymentsProvider>().account;
      if (account != null) {
        _legalName.text = account.legalName.isNotEmpty
            ? account.legalName
            : account.accountHolderName;
        _holder.text = account.accountHolderName;
        if (OwnerPaymentValidation.accountTypes.contains(account.accountType)) {
          _accountType = account.accountType;
        }
        _consent = account.setupCompleted;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _legalName.dispose();
    _mobile.dispose();
    _email.dispose();
    _holder.dispose();
    _accountNumber.dispose();
    _confirmAccountNumber.dispose();
    _ifsc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    final consentOk = OwnerPaymentValidation.validateConsent(_consent) == null;
    setState(() => _consentError = !consentOk);
    if (!formOk || !consentOk) return;

    final provider = context.read<OwnerPaymentsProvider>();
    if (provider.saving) return;

    final token = context.read<AuthProvider>().accessToken ?? '';
    final error = await provider.save(
      token: token,
      input: OwnerPaymentAccountInput(
        legalName: _legalName.text.trim(),
        accountType: _accountType,
        mobile: _mobile.text.trim(),
        email: _email.text.trim(),
        accountHolderName: _holder.text.trim(),
        bankAccountNumber: _accountNumber.text.trim(),
        confirmBankAccountNumber: _confirmAccountNumber.text.trim(),
        ifscCode: _ifsc.text.trim().toUpperCase(),
        consent: _consent,
      ),
    );

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Payment account saved. Settlements are enabled once ParkShare '
            'finishes verifying your account.',
          ),
        ),
      );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final saving = context.watch<OwnerPaymentsProvider>().saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Payments & Settlements')),
      body: SafeArea(
        child: ConstrainedContent(
          maxWidth: ResponsiveLayout.formMaxWidth,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Payment Account',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                const Text(
                  'To receive earnings from ParkShare, complete your payment '
                  'account setup.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  controller: _legalName,
                  label: 'Legal Name / Account Holder Name',
                  hint: 'As per your bank / business records',
                  prefixIcon: Icons.badge_outlined,
                  enabled: !saving,
                  textInputAction: TextInputAction.next,
                  validator: OwnerPaymentValidation.validateLegalName,
                ),
                const SizedBox(height: 14),
                _AccountTypeDropdown(
                  value: _accountType,
                  enabled: !saving,
                  onChanged: (v) => setState(() => _accountType = v),
                ),
                const SizedBox(height: 14),
                CustomTextField(
                  controller: _mobile,
                  label: 'Mobile Number',
                  hint: '10-digit mobile number',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  enabled: !saving,
                  textInputAction: TextInputAction.next,
                  validator: OwnerPaymentValidation.validateMobile,
                ),
                const SizedBox(height: 14),
                CustomTextField(
                  controller: _email,
                  label: 'Email',
                  hint: 'you@example.com',
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !saving,
                  textInputAction: TextInputAction.next,
                  validator: OwnerPaymentValidation.validateEmail,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Bank Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _holder,
                  label: 'Bank Account Holder Name',
                  prefixIcon: Icons.person_outline,
                  enabled: !saving,
                  textInputAction: TextInputAction.next,
                  validator: OwnerPaymentValidation.validateAccountHolderName,
                ),
                const SizedBox(height: 14),
                CustomTextField(
                  controller: _accountNumber,
                  label: 'Bank Account Number',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.account_balance_outlined,
                  enabled: !saving,
                  textInputAction: TextInputAction.next,
                  validator: OwnerPaymentValidation.validateAccountNumber,
                ),
                const SizedBox(height: 14),
                CustomTextField(
                  controller: _confirmAccountNumber,
                  label: 'Confirm Bank Account Number',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.check_circle_outline,
                  enabled: !saving,
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      OwnerPaymentValidation.validateConfirmAccountNumber(
                        v,
                        _accountNumber.text,
                      ),
                ),
                const SizedBox(height: 14),
                CustomTextField(
                  controller: _ifsc,
                  label: 'IFSC Code',
                  hint: 'e.g. HDFC0001234',
                  prefixIcon: Icons.pin_outlined,
                  enabled: !saving,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _submit,
                  validator: OwnerPaymentValidation.validateIfsc,
                ),
                const SizedBox(height: 16),
                _ConsentRow(
                  value: _consent,
                  enabled: !saving,
                  showError: _consentError,
                  onChanged: (v) => setState(() {
                    _consent = v;
                    if (v) _consentError = false;
                  }),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your bank details are private. They are never shown to '
                  'vehicle users and are used only to settle your earnings.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Save Payment Account',
                  icon: Icons.lock_outline,
                  loading: saving,
                  backgroundColor: AppColors.ownerPrimary,
                  onPressed: saving ? null : _submit,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountTypeDropdown extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _AccountTypeDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: 'Account Type',
        prefixIcon: const Icon(Icons.category_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: [
        for (final type in OwnerPaymentValidation.accountTypes)
          DropdownMenuItem(
            value: type,
            child: Text(OwnerPaymentValidation.accountTypeLabel(type)),
          ),
      ],
      onChanged: enabled ? (v) => onChanged(v ?? value) : null,
    );
  }
}

class _ConsentRow extends StatelessWidget {
  final bool value;
  final bool enabled;
  final bool showError;
  final ValueChanged<bool> onChanged;

  const _ConsentRow({
    required this.value,
    required this.enabled,
    required this.showError,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: value,
                  onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                  activeColor: AppColors.ownerPrimary,
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'I agree to receive ParkShare booking settlements through '
                      'the payment provider and agree to the applicable '
                      'settlement terms.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showError)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              OwnerPaymentValidation.validateConsent(false) ??
                  ErrorMessages.generic,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
