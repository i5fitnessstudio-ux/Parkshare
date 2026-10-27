import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/services/phone_call_service.dart';
import '../../../core/utils/helpers.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/booking/providers/booking_provider.dart';
import '../../../modules/inbox/providers/inbox_provider.dart';
import '../../../shared/models/booking.dart';
import '../../../shared/utils/booking_ui.dart';
import '../../../shared/widgets/empty_state.dart';

/// Vehicle-user bookings tab: statuses, pay-now for accepted bookings,
/// message-the-owner and call-the-owner (both open a real conversation /
/// the native dialler — nothing is hardcoded).
class UserBookingsTab extends StatefulWidget {
  const UserBookingsTab({super.key});

  @override
  State<UserBookingsTab> createState() => _UserBookingsTabState();
}

class _UserBookingsTabState extends State<UserBookingsTab> {
  Future<void> _messageOwner(BuildContext context, Booking b) async {
    final auth = context.read<AuthProvider>();
    final inbox = context.read<InboxProvider>();
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
        // Identify the owner by name; the parking name identifies the space.
        'title': b.ownerName.isNotEmpty ? b.ownerName : 'Parking Owner',
        'subtitle': b.apartmentLabel,
      },
    );
  }

  /// Opens the native dialler for the owner. The dialler is only pre-filled —
  /// the user still presses call, so no CALL_PHONE permission is needed.
  Future<void> _callOwner(BuildContext context, Booking b) async {
    final result = await PhoneCallService.dial(b.ownerPhone);
    if (!context.mounted) return;
    if (result == PhoneCallResult.unavailableNumber) {
      _toast(context, 'Owner phone number is unavailable.');
    } else if (result != PhoneCallResult.launched) {
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
      onRefresh: () => provider.load(
        token: auth.accessToken ?? '',
        userId: auth.user?.id ?? '',
      ),
      child: bookings.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                EmptyState(
                  icon: Icons.event_note_outlined,
                  title: 'No bookings yet',
                  subtitle:
                      'Book a parking from the map and it will appear here.',
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: bookings.length,
              itemBuilder: (context, i) => _UserBookingCard(
                booking: bookings[i],
                onMessage: () => _messageOwner(context, bookings[i]),
                onCall: () => _callOwner(context, bookings[i]),
              ),
            ),
    );
  }
}

class _UserBookingCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback onMessage;
  final VoidCallback onCall;

  const _UserBookingCard({
    required this.booking,
    required this.onMessage,
    required this.onCall,
  });

  void _pay(BuildContext context) {
    Navigator.of(context)
        .pushNamed(AppRoutes.payment, arguments: {'booking': booking});
  }

  @override
  Widget build(BuildContext context) {
    final thumbnail = booking.parking.thumbnailUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: thumbnail != null && thumbnail.isNotEmpty
                      ? Image.network(
                          thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _fallback(),
                        )
                      : _fallback(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.parking.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${RentalUi.label(booking.rentalType)} · '
                      '${Helpers.formatDate(booking.startDate)} – '
                      '${Helpers.formatDate(booking.endDate)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.currency_rupee,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          Helpers.formatRupees(booking.amount),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: BookingUi.chip(booking.status)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            // UPI / Cash on Delivery + whether the money has arrived, so a
            // COD booking never looks paid before the owner confirms it.
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                PaymentUi.methodChip(booking.paymentMethod),
                PaymentUi.statusChip(booking.paymentStatus),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            // Wrap (not Row): on narrow screens at larger text scales the two
            // owner actions and the pay/status control stack instead of
            // overflowing the card. spaceBetween keeps the original
            // "actions left, status right" look while everything fits on one
            // line.
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: onMessage,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.userPrimary,
                    side: const BorderSide(color: AppColors.userPrimary),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.chat_bubble_outline, size: 17),
                  label: const Text('Message'),
                ),
                OutlinedButton.icon(
                  key: const Key('call-owner-button'),
                  onPressed: onCall,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.userPrimary,
                    side: const BorderSide(color: AppColors.userPrimary),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.call_outlined, size: 17),
                  label: const Text('Call'),
                ),
                if (booking.status == BookingStatus.accepted ||
                    booking.status == BookingStatus.paymentPending)
                  FilledButton(
                    onPressed: () => _pay(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.userPrimary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('Pay ${Helpers.formatRupees(booking.amount)}'),
                  )
                else if (booking.status == BookingStatus.requested)
                  const Text(
                    'Waiting for owner…',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  )
                // COD chosen: the user still has to hand the cash over.
                else if (booking.status == BookingStatus.codPending)
                  const Text(
                    'Contact owner to pay cash',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  )
                else if (booking.status == BookingStatus.confirmed ||
                    booking.status == BookingStatus.active)
                  const Text(
                    'Confirmed ✓',
                    style: TextStyle(fontSize: 12, color: AppColors.success),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() => Container(
    color: AppColors.userPrimaryLight,
    child: const Icon(Icons.local_parking, color: AppColors.userPrimary),
  );
}
