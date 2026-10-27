import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/services/phone_call_service.dart';
import '../../../core/utils/helpers.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/booking/providers/booking_provider.dart';
import '../../../modules/inbox/providers/inbox_provider.dart';
import '../../../modules/owner/bookings/owner_booking_detail_sheet.dart';
import '../../../modules/owner/providers/owner_dashboard_provider.dart';
import '../../../shared/models/booking.dart';
import '../../../shared/utils/booking_ui.dart';
import '../../../shared/widgets/empty_state.dart';

/// Owner bookings tab — real joined user/parking/vehicle/payment data.
class OwnerBookingListTab extends StatefulWidget {
  const OwnerBookingListTab({super.key});

  @override
  State<OwnerBookingListTab> createState() => _OwnerBookingListTabState();
}

class _OwnerBookingListTabState extends State<OwnerBookingListTab> {
  /// Message the booked user: creates/reuses the real conversation and
  /// identifies the user by name in the chat header.
  Future<void> _messageUser(BuildContext context, Booking b) async {
    final auth = context.read<AuthProvider>();
    final inbox = context.read<InboxProvider>();
    try {
      final conversation = await inbox.ensureConversation(
        token: auth.accessToken ?? '',
        parkingId: b.parkingId,
        bookingId: b.bookingId,
      );
      if (!context.mounted) return;
      Navigator.of(context).pushNamed(
        AppRoutes.chat,
        arguments: {
          'conversationId': conversation.id,
          'title': b.userName.isNotEmpty ? b.userName : 'User',
          'subtitle': b.apartmentLabel,
        },
      );
    } catch (e) {
      ErrorMessages.logTechnical('ownerBookingMessage', e);
      if (!context.mounted) return;
      _toast(context, ErrorMessages.forUi(e));
    }
  }

  /// Opens the native dialler for the booked user (pre-filled only, so no
  /// CALL_PHONE permission is required).
  Future<void> _callUser(BuildContext context, Booking b) async {
    final result = await PhoneCallService.dial(b.userPhone);
    if (!context.mounted) return;
    switch (result) {
      case PhoneCallResult.launched:
        return;
      case PhoneCallResult.unavailableNumber:
        _toast(context, 'User phone number is unavailable.');
      case PhoneCallResult.noDialer:
      case PhoneCallResult.failed:
        _toast(context, ErrorMessages.callFailed);
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<BookingProvider>();
    final bookings = provider.bookings;

    if (provider.loading && bookings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        await provider.load(
          token: auth.accessToken ?? '',
          ownerId: auth.user?.id ?? '',
        );
      },
      child: bookings.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                EmptyState(
                  icon: Icons.event_note_outlined,
                  title: 'No booking requests yet',
                  subtitle:
                      'When a vehicle user books your parking, it shows up '
                      'here.',
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: bookings.length,
              itemBuilder: (context, i) => _BookingCard(
                booking: bookings[i],
                onMessage: () => _messageUser(context, bookings[i]),
                onCall: () => _callUser(context, bookings[i]),
              ),
            ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback onMessage;
  final VoidCallback onCall;

  const _BookingCard({
    required this.booking,
    required this.onMessage,
    required this.onCall,
  });

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OwnerBookingDetailSheet(booking: booking),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = booking.user;
    final parking = booking.parking;
    final pending = booking.status == BookingStatus.requested;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.ownerPrimaryLight,
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppColors.ownerPrimaryDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${parking.name} · ${RentalUi.label(booking.rentalType)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BookingUi.chip(booking.status),
                ],
              ),
              const SizedBox(height: 12),
              // Date/amount pair: a Wrap so the amount drops to its own line on a
              // narrow screen instead of overflowing (date left / amount right
              // while both fit).
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${Helpers.formatDate(booking.startDate)} – '
                        '${Helpers.formatDate(booking.endDate)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.currency_rupee,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        Helpers.formatRupees(booking.amount),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
              if (booking.vehicle.registrationNumber.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.directions_car_outlined,
                      size: 15,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${booking.vehicle.brand} ${booking.vehicle.model} · '
                        '${booking.vehicle.registrationNumber}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // Payment method + money state. A COD booking that has not been
              // paid yet must be obvious, and the owner action that settles it
              // sits right here on the card.
              _paymentRow(context, booking),
              if (pending) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => context.read<BookingProvider>().reject(
                          booking.bookingId,
                          token: context.read<AuthProvider>().accessToken ?? '',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => context.read<BookingProvider>().accept(
                          booking.bookingId,
                          token: context.read<AuthProvider>().accessToken ?? '',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.ownerPrimary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: onMessage,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ownerPrimaryDark,
                      side: const BorderSide(color: AppColors.ownerPrimary),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 17),
                    label: const Text('Message'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const Key('call-user-button'),
                    onPressed: onCall,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ownerPrimaryDark,
                      side: const BorderSide(color: AppColors.ownerPrimary),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.call_outlined, size: 17),
                    label: const Text('Call'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Payment method chip + money-status chip, plus the owner action that
  /// actually moves money:
  ///
  /// * "Mark COD Received" while a cash booking is still unpaid.
  ///
  /// It is the *only* thing that can turn a booking's payment into a `paid`
  /// status, and it is not offered for a payment that is already settled — so
  /// a double tap cannot double-count.
  ///
  /// Online (Razorpay) payments are verified by the payment gateway and are
  /// never confirmed manually by the owner; the owner only tracks their
  /// settlement on Payments & Settlements.
  Widget _paymentRow(BuildContext context, Booking booking) {
    final codPending = booking.status == BookingStatus.codPending;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PaymentUi.methodChip(booking.paymentMethod),
            const SizedBox(width: 6),
            PaymentUi.statusChip(booking.paymentStatus),
          ],
        ),
        if (codPending)
          ElevatedButton.icon(
            key: const Key('mark-cod-received-button'),
            onPressed: () => OwnerCodActions.confirmCod(context, booking),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.ownerPrimary,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text(
              AppStrings.codMarkReceived,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

/// The owner's "Mark COD Received" action, shared by the bookings list and the
/// detail sheet so both behave identically.
///
/// It asks for an explicit confirmation, then calls the backend, which
/// allocates the slot, flips the booking to CONFIRMED, marks the payment
/// COD_CONFIRMED and adds the amount to Total Earnings in one step.
class OwnerCodActions {
  OwnerCodActions._();

  static Future<void> confirmCod(BuildContext context, Booking booking) async {
    final token = context.read<AuthProvider>().accessToken ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.payments_outlined,
          color: AppColors.ownerPrimary,
          size: 30,
        ),
        title: const Text(AppStrings.codConfirmTitle),
        content: Text(
          '${AppStrings.codConfirmBody}\n\n'
          'Amount: ${Helpers.formatRupees(booking.amount)}  ·  '
          'Booking: ${booking.paymentReference ?? booking.bookingId}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            key: const Key('confirm-cod-dialog-yes'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ownerPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text(AppStrings.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final dashboard = context.read<OwnerDashboardProvider>();
    final ok = await dashboard.confirmCod(
      token: token,
      bookingId: booking.bookingId,
    );
    if (!context.mounted) return;

    final message = ok
        ? 'Cash payment confirmed. ${Helpers.formatRupees(booking.amount)} '
              'added to your earnings.'
        : (dashboard.error ?? 'Could not confirm the cash payment.');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    // Keep the shared BookingProvider list in step so every owner surface
    // shows CONFIRMED / COD Paid at once.
    if (ok) {
      await context.read<BookingProvider>().load(
        token: token,
        ownerId: context.read<AuthProvider>().user?.id ?? '',
      );
    }
  }
}
