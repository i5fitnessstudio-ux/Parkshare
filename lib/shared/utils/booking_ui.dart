import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../models/booking.dart';

/// Booking status -> label + chip colour mapping (shared by owner/user).
class BookingUi {
  BookingUi._();

  static String label(String status) => switch (status) {
    BookingStatus.requested => 'Requested',
    BookingStatus.accepted => 'Accepted',
    BookingStatus.rejected => 'Rejected',
    BookingStatus.paymentPending => 'Payment Pending',
    BookingStatus.codPending => 'COD Pending',
    BookingStatus.confirmed => 'Confirmed',
    BookingStatus.active => 'Active',
    BookingStatus.completed => 'Completed',
    BookingStatus.cancelled => 'Cancelled',
    _ => status,
  };

  static Color color(String status) => switch (status) {
    BookingStatus.requested => AppColors.info,
    BookingStatus.accepted => AppColors.ownerPrimary,
    BookingStatus.rejected => AppColors.error,
    BookingStatus.paymentPending => AppColors.warning,
    BookingStatus.codPending => AppColors.warning,
    BookingStatus.confirmed => AppColors.success,
    BookingStatus.active => AppColors.ownerPrimaryDark,
    BookingStatus.completed => AppColors.textSecondary,
    BookingStatus.cancelled => AppColors.error,
    _ => AppColors.textSecondary,
  };

  static Color accent(String status) => switch (status) {
    BookingStatus.requested => AppColors.info,
    BookingStatus.accepted => AppColors.success,
    BookingStatus.rejected => AppColors.error,
    BookingStatus.paymentPending => AppColors.warning,
    BookingStatus.codPending => AppColors.warning,
    BookingStatus.confirmed => AppColors.ownerPrimary,
    BookingStatus.active => AppColors.ownerPrimaryDark,
    BookingStatus.completed => AppColors.textSecondary,
    BookingStatus.cancelled => AppColors.error,
    _ => AppColors.textSecondary,
  };

  static Widget chip(String status) {
    final c = color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label(status),
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Rental type labels.
class RentalUi {
  RentalUi._();
  static String label(String type) =>
      type == RentalType.yearly ? 'Yearly' : 'Monthly';
}

/// Payment method / payment status presentation, shared by the owner and user
/// booking cards so a COD booking always looks the same on both sides.
class PaymentUi {
  PaymentUi._();

  // ---- Method ----

  /// Online (Razorpay) / UPI / Cash on Delivery. Anything else falls back to
  /// UPI so an unexpected server value can never show as a removed method
  /// (Card, NetBanking).
  static String methodLabel(String method) {
    switch (method.toUpperCase()) {
      case PaymentMethod.cod:
        return 'Cash on Delivery';
      case PaymentMethod.razorpay:
        return 'Online Payment';
      default:
        return 'UPI';
    }
  }

  static IconData methodIcon(String method) {
    switch (method.toUpperCase()) {
      case PaymentMethod.cod:
        return Icons.payments_outlined;
      case PaymentMethod.razorpay:
        return Icons.lock_outline;
      default:
        return Icons.account_balance_wallet_outlined;
    }
  }

  // ---- Status ----

  /// Confirmed / COD Pending / COD Paid / UPI Verification Pending — the states
  /// that matter for a booking involving money.
  ///
  /// Audit C-01: the unverified-UPI label must never read as a success. It says
  /// "Verification pending", and [isPaid] below returns false for it.
  static String statusLabel(String paymentStatus) =>
      switch (paymentStatus.toUpperCase()) {
        PaymentStatus.success => 'Confirmed',
        PaymentStatus.codPending => 'COD Pending',
        PaymentStatus.codConfirmed => 'COD Paid',
        PaymentStatus.upiPendingVerification => 'Verification Pending',
        PaymentStatus.pending => 'Payment Pending',
        PaymentStatus.failed => 'Failed',
        PaymentStatus.refunded => 'Refunded',
        _ => 'Not paid',
      };

  static Color statusColor(String paymentStatus) =>
      switch (paymentStatus.toUpperCase()) {
        PaymentStatus.success => AppColors.success,
        PaymentStatus.codPending => AppColors.warning,
        PaymentStatus.codConfirmed => AppColors.success,
        PaymentStatus.upiPendingVerification => AppColors.warning,
        PaymentStatus.pending => AppColors.warning,
        PaymentStatus.failed => AppColors.error,
        PaymentStatus.refunded => AppColors.textSecondary,
        _ => AppColors.textSecondary,
      };

  /// True when the owner has actually been paid.
  ///
  /// Audit C-01: this delegates to [PaymentStatus.paid], which excludes
  /// [PaymentStatus.upiPendingVerification] — a customer-asserted payment is
  /// never counted as money in hand.
  static bool isPaid(String paymentStatus) =>
      PaymentStatus.paid.contains(paymentStatus.toUpperCase());

  /// True when the customer claims a UPI transfer the owner has not verified.
  static bool isAwaitingVerification(String paymentStatus) =>
      PaymentStatus.isUnverified(paymentStatus.toUpperCase());

  /// "UPI" or "COD" chip — shows how the booking is being paid.
  static Widget methodChip(String method) => _chip(
    methodLabel(method),
    method.toUpperCase() == PaymentMethod.cod
        ? AppColors.warning
        : AppColors.ownerPrimary,
    methodIcon(method),
  );

  /// "Confirmed" / "COD Pending" / "COD Paid" chip — shows whether the money
  /// actually reached the owner.
  static Widget statusChip(String paymentStatus) =>
      _chip(statusLabel(paymentStatus), statusColor(paymentStatus), null);

  static Widget _chip(String label, Color color, IconData? icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
