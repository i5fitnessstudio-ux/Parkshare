import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/helpers.dart';
import '../../../shared/models/booking.dart';
import '../../../shared/utils/booking_ui.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Payment Successful — the receipt shown after a UPI payment is confirmed.
///
/// Shows the transaction id, the owner's UPI address and the booking
/// reference, and confirms the booking is now CONFIRMED for the owner too.
class PaymentSuccessScreen extends StatelessWidget {
  final Booking booking;

  const PaymentSuccessScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final reference = booking.paymentReference ?? booking.payment.reference;
    // Show the actual Razorpay payment id for online payments separately from
    // the booking/receipt reference.
    final transactionId = booking.isRazorpay
        ? (booking.razorpayPaymentId ?? booking.payment.razorpayPaymentId ?? booking.upiTransactionId ?? booking.payment.transactionId)
        : (booking.upiTransactionId ?? booking.payment.transactionId);

    return Scaffold(
      // No back arrow: the payment is done, the only way out is "Done".
      appBar: AppBar(
        title: const Text(AppStrings.paymentSuccessful),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ConstrainedContent(
          maxWidth: ResponsiveLayout.formMaxWidth,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 16),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    size: 60,
                    color: AppColors.success,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                AppStrings.paymentSuccessful,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                AppStrings.bookingConfirmedNote,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),

              // ---- Receipt ----
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _row('Amount paid', Helpers.formatRupees(booking.amount)),
                    // Only the legacy direct-UPI flow pays an owner UPI id. An
                    // online (Razorpay) booking must never surface the owner's
                    // personal UPI — it shows the owner's display name instead.
                    if (booking.paymentMethod == PaymentMethod.upi &&
                        (booking.ownerUpiIdUsed ?? '').isNotEmpty)
                      _row(AppStrings.paidTo, booking.ownerUpiIdUsed!),
                    if (booking.isRazorpay && booking.ownerName.isNotEmpty)
                      _row(AppStrings.paidTo, booking.ownerName),
                    if (booking.isRazorpay && transactionId.isNotEmpty)
                      _row('Payment ID', transactionId),
                    if (!booking.isRazorpay && transactionId.isNotEmpty)
                      _row(AppStrings.transactionId, transactionId),
                    if (reference != null && reference.isNotEmpty)
                      _row('Booking reference', reference),
                    _row(
                      'Payment method',
                      PaymentUi.methodLabel(booking.paymentMethod),
                    ),
                    _row('Status', BookingUi.label(booking.status)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _bookingCard(),
              const SizedBox(height: 28),
              PrimaryButton(
                label: AppStrings.done,
                icon: Icons.done_all,
                backgroundColor: AppColors.userPrimary,
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookingCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.userPrimaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_parking, color: AppColors.userPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.parking.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${RentalUi.label(booking.rentalType)} · '
                  '${Helpers.formatDate(booking.startDate)} – '
                  '${Helpers.formatDate(booking.endDate)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (booking.spaceLabel.isNotEmpty)
                  Text(
                    'Slot ${booking.spaceLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flexible instead of a fixed 130 dp column so the label can never
          // be pushed off-screen at larger text scales.
          Flexible(
            flex: 2,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
