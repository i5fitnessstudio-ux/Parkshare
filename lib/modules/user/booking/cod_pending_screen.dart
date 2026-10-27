import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/phone_call_service.dart';
import '../../../core/utils/helpers.dart';
import '../../../shared/models/booking.dart';
import '../../../shared/models/owner_payment_info.dart';
import '../../../shared/utils/booking_ui.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Cash on Delivery — shown after the user books with cash.
///
/// The booking is COD_PENDING: no money has moved, the slot is still shown as
/// available, and the amount only enters the owner's earnings once they tap
/// "Mark COD Received". This screen therefore spells out the single next step:
/// **contact the parking owner**, with their name, phone, address and (when
/// configured) their UPI id as a fallback.
class CodPendingScreen extends StatelessWidget {
  final Booking booking;
  final OwnerContact owner;

  const CodPendingScreen({
    super.key,
    required this.booking,
    required this.owner,
  });

  /// Opens the native dialler for the owner (pre-filled only, so no
  /// CALL_PHONE permission is needed).
  Future<void> _callOwner(BuildContext context) async {
    final result = await PhoneCallService.dial(owner.phone);
    if (!context.mounted) return;
    final message = switch (result) {
      PhoneCallResult.unavailableNumber =>
        'The owner phone number is unavailable. Please contact them in person.',
      PhoneCallResult.launched => null,
      _ => 'Unable to start the call.',
    };
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final reference = booking.paymentReference;
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.codTitle),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ConstrainedContent(
          maxWidth: ResponsiveLayout.formMaxWidth,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.payments_outlined,
                    size: 48,
                    color: AppColors.warning,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                AppStrings.codTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                AppStrings.codSubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                AppStrings.codInstruction,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),

              // ---- Amount due ----
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Amount to pay',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            Helpers.formatRupees(booking.amount),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (reference != null && reference.isNotEmpty) ...[
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Text(
                            'Booking reference',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              reference,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Text(
                          'Status',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: BookingUi.chip(booking.status),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ---- Owner contact ----
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.userPrimaryLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PARKING OWNER',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      owner.name.isEmpty ? 'Parking owner' : owner.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (owner.hasPhone) ...[
                      const SizedBox(height: 4),
                      Text(
                        owner.phone!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (owner.parkingName.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              owner.address.isEmpty
                                  ? owner.parkingName
                                  : '${owner.parkingName} · ${owner.address}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Cash is paid directly to the owner on handover. Personal
                    // UPI is not part of the active payment flow.
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: owner.hasPhone
                            ? () => _callOwner(context)
                            : null,
                        icon: const Icon(Icons.phone_outlined, size: 18),
                        label: const Text(AppStrings.codCallOwner),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.userPrimary,
                          side: const BorderSide(color: AppColors.userPrimary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
}
