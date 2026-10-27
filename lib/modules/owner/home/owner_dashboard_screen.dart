import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/helpers.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/booking/providers/booking_provider.dart';
import '../../../modules/inbox/inbox_tab.dart';
import '../../../modules/inbox/providers/inbox_provider.dart';
import '../../../modules/owner/bookings/owner_booking_list_tab.dart';
import '../../../modules/owner/payments/payments_settlements_screen.dart';
import '../../../modules/owner/providers/owner_dashboard_provider.dart';
import '../../../modules/owner/providers/owner_parking_provider.dart';
import '../../../modules/owner/providers/owner_payments_provider.dart';
import '../../../shared/models/booking.dart';
import '../../../shared/models/parking.dart';
import '../../../shared/utils/booking_ui.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/responsive/adaptive_nav_scaffold.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Owner navigation sections, in tab order.
const List<AdaptiveDestination> _kOwnerDestinations = [
  AdaptiveDestination(
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    label: 'Dashboard',
  ),
  AdaptiveDestination(
    icon: Icons.local_parking_outlined,
    selectedIcon: Icons.local_parking,
    label: 'Parkings',
  ),
  AdaptiveDestination(
    icon: Icons.event_note_outlined,
    selectedIcon: Icons.event_note,
    label: 'Bookings',
  ),
  AdaptiveDestination(
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    label: 'Payments',
  ),
  AdaptiveDestination(
    icon: Icons.forum_outlined,
    selectedIcon: Icons.forum,
    label: 'Inbox',
  ),
];

/// Owner home — 5 tabs: Dashboard, Parkings, Bookings, Payments, Inbox.
/// All numbers come from the backend (joined parkings + bookings), never
/// hard-coded.
class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  Future<void> _loadAll() async {
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken ?? '';
    final userId = auth.user?.id ?? '';
    await Future.wait([
      context.read<OwnerDashboardProvider>().load(
        token: token,
        ownerId: userId,
      ),
      context.read<OwnerParkingProvider>().loadMyParkings(
        token: token,
        ownerId: userId,
      ),
      context.read<BookingProvider>().load(token: token, ownerId: userId),
      context.read<InboxProvider>().loadConversations(token),
      context.read<OwnerPaymentsProvider>().load(token: token),
    ]);
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'Deleting your account will permanently remove your parking listings and history. This action cannot be undone. Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await Navigator.of(context).pushNamed(AppRoutes.deleteAccount);
    }
  }

  Future<void> _logout() async {
    final auth = context.read<AuthProvider>();
    await auth.logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.roleSelection, (r) => false);
  }

  Future<void> _openAddParking() async {
    await Navigator.of(context).pushNamed(AppRoutes.addParking);
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final firstName = (user?.name ?? '').split(' ').first;

    return AdaptiveNavScaffold(
      appBar: AppBar(
        title: Text(_tab == 3 ? 'Payments & Settlements' : 'Hi, $firstName'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') _logout();
              if (v == 'refresh') _loadAll();
              if (v == 'deleteAccount') _confirmDeleteAccount();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              const PopupMenuItem(
                value: 'logout',
                child: Text(AppStrings.logout),
              ),
              PopupMenuItem(
                value: 'deleteAccount',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Delete Account',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          // Every owner tab is a list/stats layout, so all of them cap their
          // width on desktop to keep rows readable.
          ConstrainedContent(
            maxWidth: ResponsiveLayout.contentMaxWidth,
            child: _DashboardTab(),
          ),
          ConstrainedContent(
            maxWidth: ResponsiveLayout.contentMaxWidth,
            child: _ParkingsTab(),
          ),
          ConstrainedContent(
            maxWidth: ResponsiveLayout.contentMaxWidth,
            child: OwnerBookingListTab(),
          ),
          // The Payments tab embeds the existing "Payments & Settlements"
          // surface without its own app bar; the surrounding scaffold provides
          // the title for this tab.
          PaymentsSettlementsScreen(embedded: true),
          ConstrainedContent(
            maxWidth: ResponsiveLayout.contentMaxWidth,
            child: InboxTab(),
          ),
        ],
      ),
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              onPressed: _openAddParking,
              backgroundColor: AppColors.ownerPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add Parking'),
            )
          : null,
      destinations: _kOwnerDestinations,
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard tab (stats + recent bookings)
// ---------------------------------------------------------------------------
class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<OwnerDashboardProvider>();

    if (dash.loading && dash.parkings.isEmpty && dash.bookings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        final auth = context.read<AuthProvider>();
        await dash.load(
          token: auth.accessToken ?? '',
          ownerId: auth.user?.id ?? '',
        );
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Overview',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatCard(
                label: 'Parkings',
                value: '${dash.totalParkings}',
                icon: Icons.local_parking_outlined,
                color: AppColors.ownerPrimary,
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Available',
                value: '${dash.availableParkings}',
                icon: Icons.check_circle_outline,
                color: AppColors.success,
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Occupied',
                value: '${dash.occupiedParkings}',
                icon: Icons.event_busy_outlined,
                color: AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatCard(
                label: 'Pending',
                value: '${dash.pendingRequests}',
                icon: Icons.hourglass_top_outlined,
                color: AppColors.info,
              ),
              const SizedBox(width: 10),
              // Cash bookings the owner still has to collect. This is the
              // owner's to-do list for money that has not arrived yet, so it
              // gets its own tile instead of being hidden in the bookings tab.
              _StatCard(
                label: 'COD Pending',
                value: '${dash.codPendingCount}',
                icon: Icons.payments_outlined,
                color: AppColors.warning,
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Active',
                value: '${dash.activeBookings}',
                icon: Icons.play_circle_outline,
                color: AppColors.ownerPrimaryDark,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatCard(
                label: 'Completed',
                value: '${dash.completedBookings}',
                icon: Icons.done_all_outlined,
                color: AppColors.textSecondary,
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.ownerPrimary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL EARNINGS',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Helpers.formatRupees(dash.totalEarnings),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Only money that actually arrived counts: successful
                      // online payments plus cash the owner confirmed.
                      // AUDIT C-02: this figure is the server's aggregate
                      // (`GET /api/payments/owner/earnings`); the fallback note
                      // appears when that call could not be made, so a client
                      // sum is never presented as authoritative.
                      Text(
                        '${dash.paidBookingsCount} paid booking'
                        '${dash.paidBookingsCount == 1 ? '' : 's'}'
                        ' · pending cash not included',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      if (!dash.earningsIsAuthoritative) ...[
                        const SizedBox(height: 2),
                        const Text(
                          'Offline estimate — could not reach the server',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _PaymentSetupCard(),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'Recent bookings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '${dash.bookings.length} total',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (dash.bookings.isEmpty)
            const EmptyState(
              icon: Icons.event_available_outlined,
              title: 'No bookings yet',
              subtitle: 'Bookings made against your parkings will appear here.',
            )
          else
            for (final b in dash.bookings.take(4))
              _RecentBookingRow(
                booking: b,
                // A second tap while the request is in flight must not fire a
                // second confirm, so the pill disables itself.
                confirming: dash.confirmingCod,
              ),
        ],
      ),
    );
  }
}

class _PaymentSetupCard extends StatelessWidget {
  const _PaymentSetupCard();

  @override
  Widget build(BuildContext context) {
    final pay = context.watch<OwnerPaymentsProvider>();
    final account = pay.account;
    final notStarted = account?.isNotStarted ?? true;

    // Status colours mirror the Payments & Settlements screen.
    final Color statusColor;
    final String statusText;
    if (notStarted) {
      statusColor = AppColors.warning;
      statusText = 'Not Completed';
    } else if (account!.isVerified) {
      statusColor = AppColors.success;
      statusText = 'Verified';
    } else if (account.needsAction) {
      statusColor = AppColors.error;
      statusText = account.statusLabel;
    } else {
      statusColor = AppColors.warning;
      statusText = account.statusLabel;
    }

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
          Row(
            children: [
              const Icon(
                Icons.account_balance_outlined,
                size: 18,
                color: AppColors.ownerPrimary,
              ),
              const SizedBox(width: 8),
              const Text(
                'Payment Setup',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (notStarted) ...[
            const Text(
              'Complete your payment account setup to receive ParkShare '
              'settlements.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.of(context)
                        .pushNamed(AppRoutes.ownerPaymentSetup),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ownerPrimary,
                  side: const BorderSide(color: AppColors.ownerPrimary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Set Up Payment Account'),
              ),
            ),
          ] else ...[
            Text(
              [
                if (account!.hasBank) 'Bank ${account.maskedBank}',
                'Settlement ${account.settlementLabel}',
              ].join(' · '),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            if (pay.pendingSettlementPaise > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${Helpers.formatRupees(pay.pendingSettlementPaise / 100)} '
                'pending settlement',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.ownerPayments),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ownerPrimary,
                  side: const BorderSide(color: AppColors.ownerPrimary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Payments & Settlements'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One "Recent bookings" line on the owner dashboard.
///
/// Layout rules baked in here:
///   * exactly ONE payment-method badge ("UPI" / "Cash on Delivery");
///   * exactly ONE status element, and never the same label twice — the old
///     version printed the payment state AND the booking state, so a cash
///     booking that had not been collected yet rendered "COD Pending" twice;
///   * while cash is outstanding that single status element is the actionable
///     one: tapping it opens the same confirmation dialog as the Bookings tab,
///     runs the existing COD endpoint and flips the row green ("COD Paid")
///     while Total Earnings and the COD Pending tile reload themselves
///     (OwnerDashboardProvider.confirmCod re-loads the list it renders from).
class _RecentBookingRow extends StatelessWidget {
  final Booking booking;

  /// True while any COD confirmation request is in flight.
  final bool confirming;

  const _RecentBookingRow({required this.booking, required this.confirming});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The left column takes all the slack, so a long name or parking
              // can never push the amount or the pill off the row.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.user.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${booking.parking.name} · '
                      '${RentalUi.label(booking.rentalType)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                Helpers.formatRupees(booking.amount),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              _StatusControl(booking: booking, confirming: confirming),
            ],
          ),
          const SizedBox(height: 10),
          // The single payment-method badge. How the booking is paid for is a
          // different fact from whether the money has arrived, which is what
          // the status control on the right reports.
          PaymentUi.methodChip(booking.paymentMethod),
        ],
      ),
    );
  }
}

/// The one status element of a recent-booking row.
///
/// Cash that has not been handed over yet is an owner to-do, not a passive
/// label, so it renders as a tappable pill that runs [OwnerCodActions].
/// Anything else is informational and renders as a plain chip.
class _StatusControl extends StatelessWidget {
  final Booking booking;
  final bool confirming;

  const _StatusControl({required this.booking, required this.confirming});

  @override
  Widget build(BuildContext context) {
    final moneyLabel = PaymentUi.statusLabel(booking.paymentStatus);
    final bookingLabel = BookingUi.label(booking.status);

    // Cash outstanding: the payment state and the booking state read the same
    // ("COD Pending"), so exactly one of them is shown — as the action.
    if (booking.status == BookingStatus.codPending) {
      return _CodConfirmPill(booking: booking, busy: confirming);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        BookingUi.chip(booking.status),
        // Once the cash is collected the booking state ("Confirmed") adds
        // something the money state ("COD Paid") does not, so it is worth a
        // second line. Equal labels are still collapsed into one.
        if (bookingLabel != moneyLabel) ...[
          const SizedBox(height: 4),
          _Chip(
            label: moneyLabel,
            color: PaymentUi.statusColor(booking.paymentStatus),
          ),
        ],
      ],
    );
  }
}

/// Tappable "COD Pending" pill: collects the cash through the shared COD
/// confirmation flow and then turns into a green, inert "COD Paid" pill.
class _CodConfirmPill extends StatelessWidget {
  final Booking booking;
  final bool busy;

  const _CodConfirmPill({required this.booking, required this.busy});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'COD Pending. Tap to confirm the cash received.',
      child: Material(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          // Distinct from the Bookings-tab key so the same booking does not
          // report two "mark received" targets while both tabs are alive in
          // the IndexedStack.
          key: const Key('dashboard-mark-cod-received-button'),
          borderRadius: BorderRadius.circular(999),
          onTap: busy
              ? null
              : () => OwnerCodActions.confirmCod(context, booking),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  busy ? Icons.hourglass_top : Icons.payments_outlined,
                  size: 13,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 4),
                Text(
                  'COD Pending',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small status pill used by [_StatusControl] (shared shape with
/// [BookingUi.chip], so the dashboard reads identically to the bookings tab).
class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
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

// ---------------------------------------------------------------------------
// Parkings tab (real listings + occupancy + delete)
// ---------------------------------------------------------------------------
class _ParkingsTab extends StatelessWidget {
  const _ParkingsTab();

  Future<void> _confirmDelete(
    BuildContext context,
    ParkingListing p,
    String token,
  ) async {
    final provider = context.read<OwnerParkingProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove parking?'),
        content: Text('Remove "${p.parkingName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.remove(p.id, token: token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OwnerParkingProvider>();
    final auth = context.watch<AuthProvider>();
    final parkings = provider.parkings;

    if (provider.loading && parkings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadMyParkings(
        token: auth.accessToken ?? '',
        ownerId: auth.user?.id ?? '',
      ),
      child: parkings.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                EmptyState(
                  icon: Icons.add_location_alt_outlined,
                  title: 'No parkings yet',
                  subtitle:
                      'Tap "Add Parking" to publish your first parking space.',
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: parkings.length,
              itemBuilder: (context, i) => _ParkingCard(
                parking: parkings[i],
                onDelete: () async {
                  final token = context.read<AuthProvider>().accessToken ?? '';
                  await _confirmDelete(context, parkings[i], token);
                },
                onEdit: () async {
                  // Reuses the SAME Add Parking wizard with the listing
                  // prefilled — no second edit screen, no duplicated form.
                  await Navigator.of(context).pushNamed(
                    AppRoutes.addParking,
                    arguments: {'parking': parkings[i]},
                  );
                  if (!context.mounted) return;
                  await provider.loadMyParkings(
                    token: auth.accessToken ?? '',
                    ownerId: auth.user?.id ?? '',
                  );
                },
              ),
            ),
    );
  }
}

/// Slot utilisation for one parking: a bar per vehicle type showing how many
/// of the owner's real parking spaces are currently occupied.
///
/// Every number comes from the backend's `utilisation` block (occupied space
/// count / total space count) — nothing here is computed on a guess, and a
/// partially booked lot never reads as a dead listing.
class _UtilisationBar extends StatelessWidget {
  const _UtilisationBar({required this.parking});

  final ParkingListing parking;

  @override
  Widget build(BuildContext context) {
    final u = parking.utilisation;
    final rows = <(String, int, int)>[
      if (parking.totalCarSpaces > 0)
        ('Car', u?.carSpaces.available ?? 0, parking.totalCarSpaces),
      if (parking.totalBikeSpaces > 0)
        ('Bike', u?.bikeSpaces.available ?? 0, parking.totalBikeSpaces),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, free, total) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$label spaces',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$free of $total free',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: free == 0
                            ? AppColors.warning
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : (free / total).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: AppColors.ownerPrimary.withValues(
                      alpha: 0.12,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      free == 0 ? AppColors.warning : AppColors.ownerPrimary,
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

class _ParkingCard extends StatelessWidget {
  final ParkingListing parking;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _ParkingCard({
    required this.parking,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final current = parking.currentBooking;
    final occupied = current != null;
    final statusText =
        current?['status']?.toString().replaceAll('_', ' ') ?? '';
    final thumbnail = parking.thumbnailUrl;

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
                  width: 88,
                  height: 88,
                  child: thumbnail != null && thumbnail.isNotEmpty
                      ? Image.network(
                          thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _thumbFallback(),
                        )
                      : _thumbFallback(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parking.parkingName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      parking.address,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (occupied) ...[
                          const Icon(
                            Icons.event_busy,
                            size: 15,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Occupied · $statusText',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else ...[
                          const Icon(
                            Icons.check_circle,
                            size: 15,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Available',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit parking',
                    onPressed: onEdit,
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.ownerPrimary,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove parking',
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 0,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _meta(
                      '${parking.totalCarSpaces} car · '
                      '${parking.totalBikeSpaces} bike spaces',
                    ),
                    _dot(),
                    _meta(
                      '${Helpers.feetLabel(parking.lengthM)} × '
                      '${Helpers.feetLabel(parking.widthM)} × '
                      '${Helpers.feetLabel(parking.heightM)}',
                    ),
                    if (parking.cheapestRent != null) ...[
                      _dot(),
                      _meta(Helpers.formatRupees(parking.cheapestRent!)),
                    ],
                  ],
                ),
                // Slot utilisation: how many of the owner's real spaces are
                // occupied right now, per vehicle type. A partially booked lot
                // shows "1 of 2 car spaces occupied" instead of looking dead.
                if (parking.totalSpaces > 0) ...[
                  const SizedBox(height: 10),
                  _UtilisationBar(parking: parking),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbFallback() => Container(
    color: AppColors.ownerPrimaryLight,
    child: const Icon(Icons.local_parking, color: AppColors.ownerPrimary),
  );

  Widget _meta(String text) => Text(text, style: const TextStyle(fontSize: 12));

  Widget _dot() => Container(
    width: 4,
    height: 4,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: AppColors.textHint,
      shape: BoxShape.circle,
    ),
  );
}
