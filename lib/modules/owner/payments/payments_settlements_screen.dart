import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/helpers.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/owner/providers/owner_payments_provider.dart';
import '../../../shared/models/owner_payment_info.dart';
import '../../../shared/utils/owner_payment_validation.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Owner "Payments & Settlements".
///
/// Shows the masked payout account status, whether settlements are enabled, and
/// the split between pending and settled earnings. The owner's own setup is the
/// only one reachable: the backend scopes every call to the JWT's owner id.
class PaymentsSettlementsScreen extends StatefulWidget {
  const PaymentsSettlementsScreen({super.key, this.embedded = false});

  /// When true the screen renders only its body, without its own [AppBar].
  /// The owner home embeds it as the "Payments" bottom-navigation tab, where
  /// the surrounding scaffold already provides the app bar (and shows the
  /// "Payments & Settlements" title for that tab).
  final bool embedded;

  @override
  State<PaymentsSettlementsScreen> createState() =>
      _PaymentsSettlementsScreenState();
}

class _PaymentsSettlementsScreenState extends State<PaymentsSettlementsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final token = context.read<AuthProvider>().accessToken ?? '';
    await context.read<OwnerPaymentsProvider>().load(token: token);
  }

  Future<void> _openSetup() async {
    await Navigator.of(context).pushNamed(AppRoutes.ownerPaymentSetup);
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pay = context.watch<OwnerPaymentsProvider>();
    final account = pay.account;

    final content = SafeArea(
      child: ConstrainedContent(
        maxWidth: ResponsiveLayout.formMaxWidth,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              _AccountCard(
                account: account,
                loading: pay.loading && account == null,
                onSetup: _openSetup,
              ),
              const SizedBox(height: 16),
              _SettlementSummaryCard(
                pendingSettlementPaise: pay.pendingSettlementPaise,
                settledPaise: pay.settledPaise,
                totalEarnings: pay.earnings?.totalEarnings ?? 0,
                hasSetup: pay.hasSetup,
                settlementEnabled: pay.settlementEnabled,
                onSetup: _openSetup,
              ),
              const SizedBox(height: 16),
              const _RecentSettlements(),
              const SizedBox(height: 16),
              const _PrivacyNote(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('Payments & Settlements')),
      body: content,
    );
  }
}

class _AccountCard extends StatelessWidget {
  final OwnerPaymentAccount? account;
  final bool loading;
  final VoidCallback onSetup;

  const _AccountCard({
    required this.account,
    required this.loading,
    required this.onSetup,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final notStarted = account?.isNotStarted ?? true;
    final statusColor = _statusColor(account);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Payment Account',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              _StatusChip(
                label: notStarted
                    ? 'Not Completed'
                    : (account?.statusLabel ?? 'Not Completed'),
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (notStarted) ...[
            const Text(
              'Complete your payment account setup to receive ParkShare '
              'settlements.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Set Up Payment Account',
              icon: Icons.account_balance_outlined,
              backgroundColor: AppColors.ownerPrimary,
              onPressed: onSetup,
            ),
          ] else ...[
            _DetailRow(
              label: 'Account Holder',
              value: account?.accountHolderName.isNotEmpty == true
                  ? account!.accountHolderName
                  : (account?.legalName ?? '—'),
            ),
            _DetailRow(
              label: 'Bank Account',
              value: account?.maskedBank ?? '—',
            ),
            if (account?.accountType.isNotEmpty == true)
              _DetailRow(
                label: 'Account Type',
                value: OwnerPaymentValidation.accountTypeLabel(
                  account!.accountType,
                ),
              ),
            _DetailRow(
              label: 'Settlement',
              value: account?.settlementLabel ?? 'Not Enabled',
            ),
            if (account?.needsAction == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Your payment account needs attention. Please update your '
                  'details to continue receiving settlements.',
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Update Payment Details',
              icon: Icons.edit_outlined,
              onPressed: onSetup,
            ),
          ],
        ],
      ),
    );
  }
}

class _SettlementSummaryCard extends StatelessWidget {
  final int pendingSettlementPaise;
  final int settledPaise;
  final double totalEarnings;
  final bool hasSetup;
  final bool settlementEnabled;
  final VoidCallback onSetup;

  const _SettlementSummaryCard({
    required this.pendingSettlementPaise,
    required this.settledPaise,
    required this.totalEarnings,
    required this.hasSetup,
    required this.settlementEnabled,
    required this.onSetup,
  });

  static String _rupees(int paise) => Helpers.formatRupees(paise / 100);

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settlement',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _AmountTile(
                label: 'Pending Settlement',
                value: _rupees(pendingSettlementPaise),
                color: AppColors.warning,
                icon: Icons.hourglass_bottom_outlined,
              ),
              const SizedBox(width: 12),
              _AmountTile(
                label: 'Settled Amount',
                value: _rupees(settledPaise),
                color: AppColors.success,
                icon: Icons.check_circle_outline,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'Total earnings: ${Helpers.formatRupees(totalEarnings)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasSetup)
            _InfoBanner(
              icon: Icons.info_outline,
              text:
                  'Complete your payment account setup to receive settlements. '
                  'Your earnings are recorded safely meanwhile.',
              action: onSetup,
            )
          else if (!settlementEnabled)
            const _InfoBanner(
              icon: Icons.info_outline,
              text:
                  'Settlements are Pending until ParkShare finishes payment '
                  'provider onboarding. Payment received does not mean the '
                  'amount has been paid out yet.',
            )
          else
            const _InfoBanner(
              icon: Icons.verified_outlined,
              text:
                  'Settlements are enabled. Payouts follow the provider '
                  'settlement cycle.',
            ),
          const SizedBox(height: 4),
          const Text(
            'Online payments are recorded as PENDING settlement until the '
            'payment provider transfers them. Cash on Delivery is received '
            'directly and is not part of this settlement.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _RecentSettlements extends StatelessWidget {
  const _RecentSettlements();

  @override
  Widget build(BuildContext context) {
    final entries =
        context.watch<OwnerPaymentsProvider>().earnings?.settlementEntries ??
        const <OwnerSettlementEntry>[];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent settlements',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text(
              'No online-payment settlements yet.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            )
          else
            for (final e in entries) _SettlementRow(entry: e),
        ],
      ),
    );
  }
}

class _SettlementRow extends StatelessWidget {
  final OwnerSettlementEntry entry;

  const _SettlementRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final settled = entry.isSettled;
    final title = entry.parkingName.isEmpty
        ? 'Booking ${_shortId(entry.bookingId)}'
        : entry.parkingName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Payment and settlement are independent: a booking is PAID
                // while its payout is still PENDING (or SETTLED after the
                // admin records a manual payout). The owner never settles.
                Text(
                  'Payment: ${_paymentStatusLabel(entry.paymentStatus)}'
                  ' · Settlement: ${settled ? 'SETTLED' : 'PENDING'}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Gross ${Helpers.formatRupees(entry.grossAmountPaise / 100)}'
                  ' · Fee ${Helpers.formatRupees(entry.platformFeePaise / 100)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Helpers.formatRupees(entry.ownerAmountPaise / 100),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Owner share',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.lock_outline,
          size: 16,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Your bank details are private. Vehicle users never see your '
            'account number, IFSC or settlement information.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _AmountTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? action;

  const _InfoBanner({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          if (action != null)
            TextButton(onPressed: action, child: const Text('Set Up')),
        ],
      ),
    );
  }
}

Color _statusColor(OwnerPaymentAccount? account) {
  if (account == null || account.isNotStarted) return AppColors.textSecondary;
  if (account.isVerified) return AppColors.success;
  if (account.needsAction) return AppColors.error;
  return AppColors.warning;
}

/// Short, display-only booking reference (first 8 chars of the id).
String _shortId(String? id) {
  final v = (id ?? '').trim();
  if (v.isEmpty) return '';
  return v.length <= 8 ? v : v.substring(0, 8);
}

/// Human label for a raw `payments.payment_status` value. Online (Razorpay)
/// payments settle to `SUCCESS`; both paid states render as PAID. Unknown
/// values are shown verbatim (never silently treated as paid).
String _paymentStatusLabel(String raw) {
  switch (raw.trim().toUpperCase()) {
    case 'SUCCESS':
    case 'COD_CONFIRMED':
      return 'PAID';
    case 'COD_PENDING':
      return 'COD PENDING';
    case 'UPI_PENDING_VERIFICATION':
      return 'AWAITING VERIFICATION';
    case 'CREATED':
    case 'PENDING':
      return 'PENDING';
    case 'FAILED':
      return 'FAILED';
    case 'REFUNDED':
      return 'REFUNDED';
    default:
      return raw.trim().isEmpty ? '—' : raw.trim().toUpperCase();
  }
}
