import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/helpers.dart';
import '../../../core/utils/validators.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/booking/providers/booking_provider.dart';
import '../../../modules/booking/providers/payment_provider.dart';
import '../../../shared/models/booking.dart';
import '../../../shared/models/parking.dart';
import '../../../shared/utils/booking_ui.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Payment screen — **Online Payment (Razorpay) and Cash on Delivery**.
///
/// * **Online Payment** (default) — ParkShare opens the official Razorpay
///   Checkout. The amount comes from the backend (`bookings.amount` → integer
///   paise); nothing authoritative is sent from the app. After Checkout, the
///   plugin's result is sent to the backend, which verifies the HMAC signature
///   and is the only party that can mark the booking paid.
///
///   The app never treats "the plugin said SUCCESS" as payment: the booking is
///   only confirmed from the booking the backend returns. If verification cannot
///   complete (transient network), the screen says so and offers a retry that
///   never charges again.
/// * **COD** — no money moves. The booking becomes COD_PENDING and the slot
///   stays available until the owner taps "Mark COD Received".
///
/// The legacy direct owner-UPI deep link is intentionally hidden from this
/// screen. Its code (provider + launcher/availability services) is retained so
/// the flow can be rolled back without a code change.
class PaymentScreen extends StatefulWidget {
  final Booking booking;
  final ParkingListing? parking;

  const PaymentScreen({super.key, required this.booking, this.parking});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  @override
  void initState() {
    super.initState();
    // Load the selected owner's contact details (used by the owner card and the
    // COD screen). A failure is not fatal: COD works without them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final token = context.read<AuthProvider>().accessToken ?? '';
      final parkingId = widget.parking?.id.isNotEmpty == true
          ? widget.parking!.id
          : widget.booking.parkingId;
      context.read<PaymentProvider>().loadOwnerInfo(
        token: token,
        parkingId: parkingId,
      );
    });
  }

  Booking get booking => widget.booking;

  /// Refreshes the user's booking list so CONFIRMED / COD_PENDING shows
  /// everywhere, not just on the screen that was left.
  Future<void> _refreshUserBookings() async {
    final auth = context.read<AuthProvider>();
    await context.read<BookingProvider>().load(
      token: auth.accessToken ?? '',
      userId: auth.user?.id ?? '',
    );
  }

  /// Online payment: create order → open Checkout → verify on the backend.
  Future<void> _payOnline(PaymentProvider payment) async {
    if (payment.processing) return;
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    final result = await payment.startRazorpayPayment(
      token: auth.accessToken ?? '',
      bookingId: booking.bookingId,
      prefillEmail: user?.email,
      prefillContact: user?.phone,
    );
    if (!mounted) return;

    switch (result.outcome) {
      case RazorpayOutcome.paid:
        await _refreshUserBookings();
        if (!mounted) return;
        _goToSuccess(payment);
      case RazorpayOutcome.pendingVerification:
        await _showPendingVerification(payment);
      case RazorpayOutcome.cancelled:
        showSnack(context, result.message ?? 'Payment cancelled.');
      case RazorpayOutcome.rejected:
        _showError(payment, fallback: result.message);
    }
  }

  /// Checkout reported a payment the backend has not confirmed yet. Nothing is
  /// marked paid locally; the user must not pay again.
  Future<void> _showPendingVerification(PaymentProvider payment) async {
    final message =
        payment.error ??
        'We could not confirm your payment yet. If money left your account, '
            'your booking will update automatically once the payment settles. '
            'Do not pay again.';
    final action = await showDialog<_PendingAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.hourglass_top_outlined, size: 32),
        title: const Text('Verifying payment…'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_PendingAction.checkBookings),
            child: const Text('My bookings'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_PendingAction.refresh),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.userPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Refresh status'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    switch (action) {
      case _PendingAction.refresh:
        await _retryVerification(payment);
      case _PendingAction.checkBookings:
        await _refreshUserBookings();
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      case null:
        break;
    }
  }

  /// Re-runs backend verification for the last Checkout claim. Never charges
  /// again.
  Future<void> _retryVerification(PaymentProvider payment) async {
    final auth = context.read<AuthProvider>();
    final result = await payment.retryVerify(
      token: auth.accessToken ?? '',
      bookingId: booking.bookingId,
    );
    if (!mounted) return;
    if (result.outcome == RazorpayOutcome.paid) {
      await _refreshUserBookings();
      if (!mounted) return;
      _goToSuccess(payment);
    } else if (result.outcome == RazorpayOutcome.pendingVerification) {
      showSnack(
        context,
        result.message ??
            'Still awaiting confirmation. Please check back shortly.',
      );
    } else {
      _showError(payment, fallback: result.message);
    }
  }

  Future<void> _payCod(PaymentProvider payment) async {
    final auth = context.read<AuthProvider>();
    final ok = await payment.startCod(
      token: auth.accessToken ?? '',
      bookingId: booking.bookingId,
    );
    if (!mounted) return;
    if (!ok) {
      _showError(payment, fallback: 'Cash on Delivery could not be set up.');
      return;
    }
    await _refreshUserBookings();
    if (!mounted) return;
    _goToCodPending(payment);
  }

  void _goToSuccess(PaymentProvider payment) {
    final paid = payment.paidBooking;
    if (paid == null) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.paymentSuccess,
      (route) => route.isFirst,
      arguments: paid,
    );
  }

  void _goToCodPending(PaymentProvider payment) {
    final pending = payment.paidBooking;
    if (pending == null) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.codPending,
      (route) => route.isFirst,
      arguments: {
        RouteArgs.booking: pending,
        RouteArgs.ownerContact: payment.ownerContact,
      },
    );
  }

  /// Surfaces a one-shot error. [fallback] guarantees something is shown even
  /// when the provider had nothing to say — an empty, silent failure is what
  /// made this screen appear stuck.
  void _showError(PaymentProvider payment, {String? fallback}) {
    final message = payment.error;
    payment.clearError();
    final text = (message != null && message.isNotEmpty) ? message : fallback;
    if (text != null && text.isNotEmpty) {
      showSnack(context, text, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = context.watch<PaymentProvider>();
    final isOnline = payment.method == PaymentMethod.online;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.paySecurely)),
      body: ConstrainedContent(
        maxWidth: ResponsiveLayout.contentMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _summaryCard(),
            const SizedBox(height: 20),

            const Text(
              AppStrings.choosePaymentMethod,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),

            // ---- Online payment (Razorpay) ----
            _methodTile(
              method: PaymentMethod.online,
              icon: Icons.lock_outline,
              title: 'Online Payment',
              subtitle: 'Razorpay — UPI, cards, wallets & netbanking',
              enabled: true,
              selected: isOnline,
              onTap: () => payment.selectMethod(PaymentMethod.online),
            ),

            // ---- Cash on Delivery ----
            const SizedBox(height: 12),
            _methodTile(
              method: PaymentMethod.cod,
              icon: Icons.payments_outlined,
              title: AppStrings.codTitle,
              subtitle: 'Pay the owner in cash when you park',
              enabled: true,
              selected: !isOnline,
              onTap: () => payment.selectMethod(PaymentMethod.cod),
            ),

            const SizedBox(height: 20),
            _ownerCard(),
            const SizedBox(height: 12),
            _secureNotice(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: ConstrainedContent(
          maxWidth: ResponsiveLayout.formMaxWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: PrimaryButton(
              label: _buttonLabel(payment, isOnline),
              // Verifying an online payment counts as loading: the button shows
              // a spinner until the backend has confirmed, so the label and the
              // enabled state can never disagree.
              loading: payment.processing || payment.loadingOwnerInfo,
              icon: isOnline ? Icons.lock_outline : Icons.payments_outlined,
              backgroundColor: AppColors.userPrimary,
              onPressed: (payment.processing || payment.loadingOwnerInfo)
                  ? null
                  : () => isOnline ? _payOnline(payment) : _payCod(payment),
            ),
          ),
        ),
      ),
    );
  }

  String _buttonLabel(PaymentProvider payment, bool isOnline) {
    if (payment.isAwaitingRazorpay) return 'Verifying payment…';
    return isOnline
        ? '${AppStrings.payNow} ${Helpers.formatRupees(booking.amount)}'
        : '${AppStrings.bookOnCash} · ${Helpers.formatRupees(booking.amount)}';
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.parking?.parkingName ?? booking.parking.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            '${RentalUi.label(booking.rentalType)} · '
            '${Helpers.formatDate(booking.startDate)} – '
            '${Helpers.formatDate(booking.endDate)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          if (booking.spaceLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Slot ${booking.spaceLabel}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          const Divider(height: 24),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  Helpers.formatRupees(booking.amount),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _methodTile({
    required String method,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final border = selected && enabled
        ? AppColors.userPrimary
        : AppColors.border;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: selected ? 1.6 : 1),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: enabled ? AppColors.userPrimary : AppColors.textHint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected && enabled
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected && enabled
                  ? AppColors.userPrimary
                  : AppColors.textHint,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// The owner being paid. ParkShare never shows the owner's personal UPI id
  /// on the online (Razorpay) or Cash on Delivery flow: payouts are settled by
  /// ParkShare, not by a direct person-to-person transfer.
  Widget _ownerCard() {
    final owner = context.watch<PaymentProvider>().ownerInfo;
    final name = owner?.ownerName.isNotEmpty == true
        ? owner!.ownerName
        : booking.ownerName;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storefront_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              const Text(
                'PAYING THE PARKING OWNER',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            name.isEmpty ? 'Parking owner' : name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ],
      ),
    );
  }

  /// Reassurance about how the online payment is handled. ParkShare never sees
  /// or stores card / UPI-PIN data, and the key secret stays on the server.
  Widget _secureNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, size: 18, color: AppColors.info),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Online payments are processed securely by Razorpay. ParkShare '
              'never stores your card details or UPI PIN.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PendingAction { refresh, checkBookings }
