import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/helpers.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/vehicle/providers/vehicle_provider.dart';
import '../../../shared/models/vehicle.dart';
import '../../../shared/widgets/empty_state.dart';

/// Vehicle User's vehicles tab — add / edit / delete saved vehicles. The
/// vehicle dimensions drive the parking fit check.
class VehiclesTab extends StatelessWidget {
  const VehiclesTab({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    Vehicle v,
    String token,
  ) async {
    final provider = context.read<VehicleProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove vehicle?'),
        content: Text('Remove ${v.displayName}?'),
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
      await provider.delete(v.id, token: token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VehicleProvider>();
    final auth = context.watch<AuthProvider>();
    final vehicles = provider.vehicles;

    return Scaffold(
      body: provider.loading && vehicles.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  provider.loadMyVehicles(token: auth.accessToken ?? ''),
              child: vehicles.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        const EmptyState(
                          icon: Icons.two_wheeler_outlined,
                          title: 'No vehicles added',
                          subtitle:
                              'Add your bike or car so the fit check can work.',
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: FilledButton.icon(
                            onPressed: () =>
                                Navigator.of(context)
                                    .pushNamed(AppRoutes.vehicleForm),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.userPrimary,
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Add vehicle'),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      itemCount: vehicles.length,
                      itemBuilder: (context, i) {
                        final v = vehicles[i];
                        return _VehicleCard(
                          vehicle: v,
                          onEdit: () => Navigator.of(context).pushNamed(
                            AppRoutes.vehicleForm,
                            arguments: {'vehicle': v},
                          ),
                          onDelete: () => _confirmDelete(
                            context,
                            v,
                            auth.accessToken ?? '',
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: vehicles.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.vehicleForm),
              backgroundColor: AppColors.userPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final Vehicle vehicle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VehicleCard({
    required this.vehicle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isBike = vehicle.isBike;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.userPrimaryLight,
                child: Icon(
                  isBike ? Icons.two_wheeler : Icons.directions_car,
                  color: AppColors.userPrimaryDark,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            vehicle.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (vehicle.isPrimary) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.userPrimaryLight,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'PRIMARY',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppColors.userPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicle.registrationNumber,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'L ${Helpers.feetLabel(vehicle.lengthM)} × '
                      'W ${Helpers.feetLabel(vehicle.widthM)} × '
                      'H ${Helpers.feetLabel(vehicle.heightM)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textHint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
