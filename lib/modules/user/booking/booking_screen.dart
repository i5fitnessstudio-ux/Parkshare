import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/services/fit_check_service.dart';
import '../../../core/services/parking_service.dart';
import '../../../core/utils/helpers.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/booking/providers/booking_provider.dart';
import '../../../modules/vehicle/providers/vehicle_provider.dart';
import '../../../shared/models/booking.dart';
import '../../../shared/models/parking.dart';
import '../../../shared/models/parking_space.dart';
import '../../../shared/models/vehicle.dart';
import '../../../shared/utils/booking_ui.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Booking screen — pick vehicle, rental plan, start date; the amount is
/// computed server-side. Submits to the backend which re-validates vehicle
/// type + fit + date overlaps.
///
/// Availability is SLOT-based: a booking takes exactly one physical space
/// (C1, C2, B1 …) for the window, so one taken slot never makes the whole
/// property disappear. The screen probes the selected window against the
/// vehicle's real dimensions; the server's authoritative check runs on submit
/// and its 409 always wins. Both paths surface the same professional copy —
/// "Bike Parking Full", "Your vehicle may not fit…" — never a status code.
class BookingScreen extends StatefulWidget {
  final ParkingListing parking;
  const BookingScreen({super.key, required this.parking});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  String _rentalType = RentalType.monthly;
  Vehicle? _vehicle;
  DateTime _start = DateTime.now();
  bool _submitting = false;
  bool _checkingDates = false;

  /// Server-computed slot availability for the selected window + vehicle.
  /// `null` = not probed yet, or the probe failed, in which case the server
  /// decides on submit.
  ParkingAvailability? _availability;

  ParkingListing get parking => widget.parking;

  @override
  void initState() {
    super.initState();
    _vehicle = _defaultVehicle();
    _syncRentalType();
    // The slot pools on this screen are LIVE, so probe the default window as
    // soon as it opens. Without this the user lands on a blank "—" for both
    // pools and has to guess that changing a date is what fills them in.
    // Post-frame: [\_checkDates] calls setState, which is illegal during the
    // first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkDates();
    });
  }

  /// The rental plan also changes the end date (monthly vs yearly), so the
  /// probed window is keyed on both plus the vehicle (it decides the fit).
  String get _windowKey =>
      '$_rentalType|${_isoDate(_start)}|${_isoDate(_end)}|${_vehicle?.id ?? ''}';

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Only vehicles the listing actually has slots for. A car is never offered
  /// on a bike-only listing (the slot list, not a flag, decides).
  List<Vehicle> get _bookableVehicles {
    final all = context.read<VehicleProvider>().vehicles;
    final cars = parking.spaces.where((s) => s.isCar).length;
    final bikes = parking.spaces.where((s) => s.isBike).length;
    // No slot data (pre-migration listing) falls back to the accepted type.
    if (cars == 0 && bikes == 0) {
      return all
          .where(
            (v) => FitCheckService.vehicleAllowed(
              parking.vehicleType,
              v.vehicleType,
            ),
          )
          .toList(growable: false);
    }
    return all
        .where((v) => v.vehicleType == 'BIKE' ? bikes > 0 : cars > 0)
        .toList(growable: false);
  }

  Vehicle? _defaultVehicle() {
    final all = context.read<VehicleProvider>().vehicles;
    final cars = parking.spaces.where((s) => s.isCar).length;
    final bikes = parking.spaces.where((s) => s.isBike).length;
    for (final v in all) {
      if (cars == 0 && bikes == 0) {
        if (FitCheckService.vehicleAllowed(
          parking.vehicleType,
          v.vehicleType,
        )) {
          return v;
        }
      } else if (v.vehicleType == 'BIKE' ? bikes > 0 : cars > 0) {
        return v;
      }
    }
    return all.isNotEmpty ? all.first : null;
  }

  DateTime get _end {
    if (_rentalType == RentalType.yearly) {
      return DateTime(
        _start.year + 1,
        _start.month,
        _start.day,
      ).subtract(const Duration(days: 1));
    }
    return DateTime(
      _start.year,
      _start.month + 1,
      _start.day,
    ).subtract(const Duration(days: 1));
  }

  /// The plan that applies to the picked vehicle. Before a vehicle is chosen
  /// a plan counts as available when EITHER vehicle type offers it.
  RentPlan get _plan => parking.planFor(_vehicle?.vehicleType);

  /// Plans are per vehicle type: when the picked vehicle's plan drops the
  /// selected rental type, snap to the one it still offers (monthly first).
  void _syncRentalType() {
    final plan = _plan;
    if (_rentalType == RentalType.monthly &&
        !plan.monthlyEnabled &&
        plan.yearlyEnabled) {
      _rentalType = RentalType.yearly;
    } else if (_rentalType == RentalType.yearly &&
        !plan.yearlyEnabled &&
        plan.monthlyEnabled) {
      _rentalType = RentalType.monthly;
    }
  }

  double? get _rentEstimate {
    if (_rentalType == RentalType.yearly) {
      return _plan.yearlyEnabled ? _plan.yearlyRent : null;
    }
    return _plan.monthlyEnabled ? _plan.monthlyRent : null;
  }

  /// Why the selected window is not bookable, in the user's words, or `null`
  /// when it is. Ordered so the "nothing matches" case never reads as "full".
  String? get _blockedReason {
    final a = _availability;
    if (a == null || a.isAvailable) return null;
    if (a.totalSpaces == 0) {
      return a.legacyParkingBlocked
          ? ErrorMessages.dateConflict
          : ErrorMessages.noSpacesAvailable;
    }
    if (a.availableSpaces == 0 && !a.fitsAnySpace) {
      return ErrorMessages.noSuitableSpace;
    }
    return ErrorMessages.parkingFull(a.vehicleType);
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) await _applyWindow(() => _start = picked);
  }

  /// Applies a new window (optional state change) and re-probes availability.
  Future<void> _applyWindow([VoidCallback? update]) async {
    if (update != null) setState(update);
    await _checkDates();
  }

  /// Read-only probe of the selected window. Never blocks the submit button on
  /// its own: a failed probe leaves [\_availability] null and the server's
  /// authoritative check still decides.
  Future<void> _checkDates() async {
    final key = _windowKey;
    final token = context.read<AuthProvider>().accessToken ?? '';
    setState(() {
      _checkingDates = true;
      _availability = null;
    });
    try {
      final result = await ParkingService().checkAvailability(
        parkingId: parking.id,
        startDate: _start,
        endDate: _end,
        token: token,
        // The saved vehicle's real dimensions decide which slots it fits in.
        vehicleId: _vehicle?.id,
        vehicleType: _vehicle?.vehicleType,
      );
      if (!mounted || key != _windowKey) return;
      setState(() {
        _checkingDates = false;
        _availability = result;
      });
    } catch (e) {
      ErrorMessages.logTechnical('availability', e);
      if (!mounted || key != _windowKey) return;
      // Probe failure is non-fatal: fall back to the server's own check.
      setState(() {
        _checkingDates = false;
        _availability = null;
      });
    }
  }

  /// The one conflict dialog. [Change Dates] opens the date picker again,
  /// [OK] dismisses. No technical detail, no status code, no stack text.
  ///
  /// [override] is used for the authoritative server rejection: whatever the
  /// probe said, the 409 from `POST /api/bookings` wins, so the dialog is
  /// always titled "Parking Unavailable" and the copy says the space "was just
  /// booked" — never "409" or "ApiException", and never a "Full" claim that
  /// depends on a probe that may itself have failed.
  Future<void> _showUnavailable({String? override}) async {
    final reason = override ?? _blockedReason ?? ErrorMessages.dateConflict;
    final changeDates = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.event_busy_outlined,
          color: AppColors.warning,
          size: 32,
        ),
        title: Text(
          override != null || _availability?.isFullForVehicle != true
              ? 'Parking Unavailable'
              : '${_availability!.vehicleLabel} Parking Full',
        ),
        content: Text(reason),
        actions: [
          TextButton(
            // true -> reopen the date picker (see the check below).
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Change Dates'),
          ),
          FilledButton(
            // false -> plain dismissal, stay on the booking form.
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.userPrimary,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (changeDates == true) {
      // _pickStart re-probes the new window.
      await _pickStart();
    }
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final provider = context.read<BookingProvider>();
    final vehicle = _vehicle;
    if (vehicle == null) return;

    // Pre-flight the window so the user gets the conflict dialog before a
    // write attempt. A probe failure is ignored — submit anyway.
    await _checkDates();
    if (!mounted) return;
    if (_blockedReason != null) {
      await _showUnavailable();
      return;
    }

    setState(() => _submitting = true);
    try {
      final booking = await provider.create(
        token: auth.accessToken ?? '',
        parkingId: parking.id,
        vehicleId: vehicle.id,
        rentalType: _rentalType,
        startDate: '${_isoDate(_start)}T00:00:00.000Z',
        endDate: '${_isoDate(_end)}T23:59:59.000Z',
      );
      if (!mounted) return;

      if (booking.status == BookingStatus.accepted ||
          booking.status == BookingStatus.paymentPending) {
        // Auto-approved: straight to payment.
        Navigator.of(context).pushReplacementNamed(
          AppRoutes.payment,
          arguments: {'booking': booking, 'parking': parking},
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              booking.status == BookingStatus.requested
                  ? 'Booking requested for ${booking.spaceLabel}. '
                        'The owner will confirm shortly.'
                  : 'Booking ${booking.status.toLowerCase()}.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      // Another booking took the last matching slot between the probe and the
      // write (or the probe was skipped): the server's 409 wins. Re-probe so
      // the dialog names the vehicle type, then show it.
      if (e is ApiException && e.type == ApiErrorType.conflict) {
        ErrorMessages.logTechnical('createBooking', e);
        await _checkDates();
        if (!mounted) return;
        await _showUnavailable(override: ErrorMessages.parkingUnavailable);
        return;
      }
      ErrorMessages.logTechnical('createBooking', e);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(ErrorMessages.forUi(e))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allVehicles = context.watch<VehicleProvider>().vehicles;
    final vehicles = _bookableVehicles;
    final estimate = _rentEstimate;

    return Scaffold(
      appBar: AppBar(title: const Text('Book Parking')),
      body: ConstrainedContent(
        maxWidth: ResponsiveLayout.contentMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Parking summary
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.local_parking,
                    color: AppColors.userPrimary,
                    size: 28,
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
                        ),
                        Text(
                          parking.address,
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
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Vehicle selection. Only vehicles with a matching parking space are
            // offered — the slot list decides, never a hardcoded flag.
            Text(
              'Your vehicle',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (vehicles.isNotEmpty)
              DropdownButtonFormField<Vehicle>(
                initialValue: vehicles.contains(_vehicle)
                    ? _vehicle
                    : vehicles.first,
                isExpanded: true,
                decoration: _inputDeco(),
                items: [
                  for (final v in vehicles)
                    DropdownMenuItem(
                      value: v,
                      child: Text(
                        v.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => _applyWindow(() {
                  _vehicle = v;
                  _syncRentalType();
                }),
              ),
            if (allVehicles.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Add a vehicle in the Vehicles tab first.',
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                ),
              )
            else if (vehicles.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 14,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'This parking only has '
                        '${parking.spaces.where((s) => s.isBike).isEmpty ? 'car' : 'bike'} '
                        'parking spaces, so none of your vehicles fit here.',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Rental plan
            Text('Rental plan', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _planTile(
                    'Monthly',
                    _plan.monthlyEnabled,
                    onTap: _plan.monthlyEnabled
                        ? () => _applyWindow(
                            () => _rentalType = RentalType.monthly,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _planTile(
                    'Yearly',
                    _plan.yearlyEnabled,
                    onTap: _plan.yearlyEnabled
                        ? () => _applyWindow(
                            () => _rentalType = RentalType.yearly,
                          )
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Dates
            Text('Start date', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _applyWindow(),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      color: AppColors.userPrimary,
                    ),
                    const SizedBox(width: 10),
                    // Two equal halves: the end date stays flush right while
                    // both can shrink instead of overflowing.
                    Expanded(
                      child: Text(
                        Helpers.formatDate(_start),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        Helpers.formatDate(_end),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${RentalUi.label(_rentalType)} plan: '
              '${Helpers.formatDate(_start)} – ${Helpers.formatDate(_end)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            // Live slot availability for the selected window. `null` = not
            // probed yet or the probe failed, in which case the server decides
            // on submit. The wording comes from the server's own numbers.
            if (_checkingDates)
              Row(
                children: [
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.userPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Checking these dates…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              )
            else if (_availability != null && _availability!.isAvailable)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 15,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _availability!.statusLine,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            else if (_blockedReason != null)
              Row(
                children: [
                  Icon(
                    _availability?.isFullForVehicle == true
                        ? Icons.do_not_disturb_on_outlined
                        : Icons.event_busy_outlined,
                    size: 15,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _blockedReason!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_availability?.isFullForVehicle == true)
                    TextButton(
                      onPressed: _showUnavailable,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.userPrimary,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Change Dates'),
                    ),
                ],
              ),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.userPrimaryLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.userPrimary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Estimated amount (final amount is computed '
                      'by the server)',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    estimate != null ? Helpers.formatRupees(estimate) : '—',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: ConstrainedContent(
          maxWidth: ResponsiveLayout.formMaxWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: PrimaryButton(
              label: 'Submit Booking',
              loading: _submitting,
              onPressed: _submitting || _vehicle == null ? null : _submit,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco() => InputDecoration(
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border),
    ),
  );

  Widget _planTile(String label, bool enabled, {VoidCallback? onTap}) {
    final selected =
        _rentalType ==
        (label == 'Monthly' ? RentalType.monthly : RentalType.yearly);
    final color = !enabled
        ? AppColors.textHint
        : selected
        ? AppColors.userPrimary
        : AppColors.textSecondary;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.userPrimary : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              !enabled
                  ? 'Unavailable'
                  : Helpers.formatRupees(_rentOf(label) ?? 0),
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }

  double? _rentOf(String label) =>
      label == 'Monthly' ? _plan.monthlyRent : _plan.yearlyRent;
}
