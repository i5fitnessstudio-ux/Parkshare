import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/services/phone_call_service.dart';
import '../../../core/utils/helpers.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/inbox/providers/inbox_provider.dart';
import '../../../modules/owner/bookings/owner_booking_list_tab.dart';
import '../../../shared/models/booking.dart';
import '../../../shared/utils/booking_ui.dart';

/// Owner booking detail — REAL joined user/parking/vehicle/payment data with
/// Call / Message / View Details actions.
class OwnerBookingDetailSheet extends StatelessWidget {
  final Booking booking;

  const OwnerBookingDetailSheet({super.key, required this.booking});

  /// Opens the native dialler for the booked user. The dialler is only
  /// pre-filled (the user still presses call), so no CALL_PHONE permission.
  Future<void> _call(BuildContext context) async {
    final result = await PhoneCallService.dial(booking.userPhone);
    if (!context.mounted) return;
    final message = switch (result) {
      PhoneCallResult.unavailableNumber => 'User phone number is unavailable.',
      PhoneCallResult.launched => null,
      _ => ErrorMessages.callFailed,
    };
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _message(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken ?? '';
    final inbox = context.read<InboxProvider>();
    try {
      final conversation = await inbox.ensureConversation(
        token: token,
        parkingId: booking.parkingId,
        bookingId: booking.bookingId,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop(); // close the sheet
      Navigator.of(context).pushNamed(
        AppRoutes.chat,
        arguments: {
          'conversationId': conversation.id,
          'title': booking.userName.isNotEmpty ? booking.userName : 'User',
          'subtitle': booking.apartmentLabel,
        },
      );
    } catch (e) {
      ErrorMessages.logTechnical('ownerBookingMessage', e);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(ErrorMessages.forUi(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = booking.user;
    final vehicle = booking.vehicle;
    final payment = booking.payment;
    final reference = booking.paymentReference ?? payment.reference;
    final transactionId = booking.isRazorpay
        ? (booking.razorpayPaymentId ?? payment.razorpayPaymentId ?? booking.upiTransactionId ?? payment.transactionId)
        : (booking.upiTransactionId ?? payment.transactionId);
    final codConfirmedAt = booking.codConfirmedAt;
    // Cash bookings get a collected-cash receipt id, not a UPI transaction, so
    // the row must not claim to be a "Txn ID".
    final isCod = booking.paymentMethod.toUpperCase() == PaymentMethod.cod;
    // Razorpay: verification is the gateway's HMAC, never an owner action.
    final isRazorpay = booking.isRazorpay;
    final razorpayPaid =
        booking.paymentStatus.toUpperCase() == PaymentStatus.success;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Booking Details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                BookingUi.chip(booking.status),
              ],
            ),
            const SizedBox(height: 10),
            // Payment method (UPI / Cash on Delivery) + money status, so the
            // owner always knows whether this booking has been paid.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                PaymentUi.methodChip(booking.paymentMethod),
                PaymentUi.statusChip(booking.paymentStatus),
              ],
            ),
            const SizedBox(height: 16),

            // Customer
            Container(
              padding: const EdgeInsets.all(14),
              decoration: _box(),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.ownerPrimaryLight,
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppColors.ownerPrimaryDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CUSTOMER',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if (booking.userPhone != null)
                          Text(
                            booking.userPhone!,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _roundIcon(Icons.phone_outlined, () => _call(context)),
                      const SizedBox(height: 8),
                      _roundIcon(
                        Icons.chat_bubble_outline,
                        () => _message(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Details (View Details content is the sheet itself)
            _section(
              context,
              'Parking',
              icon: Icons.local_parking_outlined,
              child: _kv([
                ('Name', booking.parking.name),
                ('Address', booking.parking.address),
              ]),
            ),
            _section(
              context,
              'Vehicle',
              icon: Icons.directions_car_outlined,
              child: _kv([
                ('Type', vehicle.type == 'BIKE' ? 'Bike' : 'Car'),
                ('Make', '${vehicle.brand} ${vehicle.model}'),
                ('Registration', vehicle.registrationNumber),
              ]),
            ),
            _section(
              context,
              'Rental & Dates',
              icon: Icons.event_available_outlined,
              child: _kv([
                ('Plan', RentalUi.label(booking.rentalType)),
                ('Start', Helpers.formatDate(booking.startDate)),
                ('End', Helpers.formatDate(booking.endDate)),
                ('Amount', Helpers.formatRupees(booking.amount)),
              ]),
            ),
            _section(
              context,
              'Payment',
              icon: Icons.payment_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv([
                    ('Method', PaymentUi.methodLabel(payment.paymentMethod)),
                    (
                      'Status',
                      PaymentUi.statusLabel(
                        booking.paymentStatus.isNotEmpty
                            ? booking.paymentStatus
                            : payment.paymentStatus,
                      ),
                    ),
                    if (isRazorpay)
                      (
                        'Verification',
                        razorpayPaid ? 'Verified by Razorpay' : 'Processing',
                      ),
                    // Payment PAID does not mean the owner has been settled:
                    // Razorpay transfers are a separate, later step. The owner
                    // tracks the payout on Payments & Settlements.
                    if (isRazorpay && razorpayPaid)
                      ('Settlement', 'Pending — see Payments & Settlements'),
                    if (reference != null) ('Booking reference', reference),
                    if (transactionId.isNotEmpty)
                      (isRazorpay ? 'Payment ID' : (isCod ? 'Receipt ID' : 'Txn ID'), transactionId),
                    if (codConfirmedAt != null)
                      ('Cash received', Helpers.formatDateTime(codConfirmedAt)),
                  ]),
                  // The single action that settles a cash booking.
                  if (booking.status == BookingStatus.codPending) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        key: const Key('mark-cod-received-button'),
                        onPressed: () =>
                            OwnerCodActions.confirmCod(context, booking),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.ownerPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text(AppStrings.codMarkReceived),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Created ${Helpers.formatDateTime(booking.createdAt)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.ownerPrimaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.ownerPrimaryDark, size: 20),
      ),
    );
  }

  BoxDecoration _box() => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AppColors.border),
  );

  Widget _section(
    BuildContext context,
    String title, {
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.ownerPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _kv(List<(String, String)> rows) {
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
