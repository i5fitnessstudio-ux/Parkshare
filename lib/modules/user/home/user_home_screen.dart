import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/booking/providers/booking_provider.dart';
import '../../../modules/inbox/inbox_tab.dart';
import '../../../modules/inbox/providers/inbox_provider.dart';
import '../../../modules/shared/providers/location_provider.dart';
import '../../../modules/user/bookings/user_bookings_tab.dart';
import '../../../modules/user/map/user_map_tab.dart';
import '../../../modules/user/providers/user_home_tab_provider.dart';
import '../../../modules/vehicle/providers/vehicle_provider.dart';
import '../../../modules/vehicle/vehicle_tab.dart';
import '../../../shared/widgets/responsive/adaptive_nav_scaffold.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Vehicle-user navigation sections, in tab order.
const List<AdaptiveDestination> _kUserDestinations = [
  AdaptiveDestination(
    icon: Icons.directions_car_outlined,
    selectedIcon: Icons.directions_car,
    label: 'Vehicles',
  ),
  AdaptiveDestination(
    icon: Icons.map_outlined,
    selectedIcon: Icons.map,
    label: 'Map',
  ),
  AdaptiveDestination(
    icon: Icons.event_note_outlined,
    selectedIcon: Icons.event_note,
    label: 'Bookings',
  ),
  AdaptiveDestination(
    icon: Icons.forum_outlined,
    selectedIcon: Icons.forum,
    label: 'Inbox',
  ),
];

/// Vehicle User home — 4 tabs in this order: Vehicles, Map, Bookings, Inbox.
/// Vehicles is the landing tab after login/register.
///
/// The selected tab lives in [UserHomeTabProvider] rather than local state, so
/// another screen (the vehicle form's "Save & Find Parking") can switch to the
/// Map tab without pushing a duplicate map route.
class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  /// Pull-to-refresh / overflow "Refresh" re-runs the same initial load.
  Future<void> _loadInitial() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final token = auth.accessToken ?? '';
    final userId = auth.user?.id ?? '';
    // Fire-and-forget: preload never prompts and never throws.
    unawaited(context.read<LocationProvider>().preload());
    await Future.wait([
      context.read<VehicleProvider>().loadMyVehicles(token: token),
      context.read<BookingProvider>().load(token: token, userId: userId),
      context.read<InboxProvider>().loadConversations(token),
    ]);
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'Deleting your account will permanently remove your account and history. This action cannot be undone. Are you sure you want to continue?',
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final firstName = (user?.name ?? '').split(' ').first;
    final tabIndex = context.select<UserHomeTabProvider, int>((p) => p.index);

    return AdaptiveNavScaffold(
      appBar: AppBar(
        title: Text('Hi, $firstName'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') _logout();
              if (v == 'refresh') _loadInitial();
              if (v == 'deleteAccount') _confirmDeleteAccount();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              const PopupMenuItem(value: 'logout', child: Text(AppStrings.logout)),
              PopupMenuItem(
                value: 'deleteAccount',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: AppColors.error, size: 18),
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
        index: tabIndex,
        // NOTE: intentionally not `const` — the map needs the active flag to
        // defer its location permission prompt until the user opens the Map.
        children: [
          // List tabs cap their width on desktop so rows stay readable; the
          // Map tab stays full-bleed.
          const ConstrainedContent(
            maxWidth: ResponsiveLayout.contentMaxWidth,
            child: VehiclesTab(),
          ),
          UserMapTab(active: tabIndex == UserTab.map.index),
          const ConstrainedContent(
            maxWidth: ResponsiveLayout.contentMaxWidth,
            child: UserBookingsTab(),
          ),
          const ConstrainedContent(
            maxWidth: ResponsiveLayout.contentMaxWidth,
            child: InboxTab(),
          ),
        ],
      ),
      destinations: _kUserDestinations,
      selectedIndex: tabIndex,
      onDestinationSelected: (i) =>
          context.read<UserHomeTabProvider>().showIndex(i),
    );
  }
}
