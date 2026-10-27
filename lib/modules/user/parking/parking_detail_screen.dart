import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/services/fit_check_service.dart';
import '../../../core/services/parking_service.dart';
import '../../../core/utils/helpers.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/vehicle/providers/vehicle_provider.dart';
import '../../../shared/models/parking.dart';
import '../../../shared/models/parking_space.dart';
import '../../../shared/models/vehicle.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Parking detail — real listing data, slot availability for the user's actual
/// vehicle, the individual parking spaces, fit check and booking entry.
///
/// The whole screen answers ONE question honestly: "for my vehicle, on these
/// dates, can I actually park here?" Everything the user sees — the per-type
/// counts, the greyed-out slots and the state of the "Book This Parking" button
/// — is derived from the server's slot-level availability for the selected
/// window. A listing with 3 car spaces is never presented as "3 spaces free".
class ParkingDetailScreen extends StatefulWidget {
  final String parkingId;
  final ParkingListing? parking;

  const ParkingDetailScreen({super.key, required this.parkingId, this.parking});

  @override
  State<ParkingDetailScreen> createState() => _ParkingDetailScreenState();
}

class _ParkingDetailScreenState extends State<ParkingDetailScreen> {
  final ParkingService _service = ParkingService();

  ParkingListing? _parking;
  Vehicle? _selectedVehicle;
  bool _loading = true;
  bool _refreshing = false;
  String? _loadError;
  int _photoIndex = 0;

  /// Start of the window every availability number on this screen describes.
  /// Defaults to today, which is also where the booking form starts, so the
  /// counts here and the verdict there never contradict each other.
  DateTime _start = _today();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// End of the checked window: one month minus a day, mirroring the booking
  /// form's default monthly plan.
  DateTime get _end => DateTime(
    _start.year,
    _start.month + 1,
    _start.day,
  ).subtract(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _parking = widget.parking;
    // Defer past the build phase: loadMyVehicles() calls notifyListeners()
    // synchronously, which crashes "setState() during build" if invoked from
    // initState. Same post-frame pattern as the other list-loading screens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final auth = context.read<AuthProvider>();
    final vehicleProvider = context.read<VehicleProvider>();
    await vehicleProvider.loadMyVehicles(token: auth.accessToken ?? '');

    var parking = _parking;
    // The vehicle decides WHICH slots count, so it is resolved BEFORE the read:
    // the first fetch already asks for per-slot availability for this window.
    _selectedVehicle = _firstCompatible(parking);
    try {
      // Always refresh from the backend so the booking screen never receives
      // a stale object (e.g. an older nearby snapshot or a drafts-cached one).
      parking = await _fetch();
      _parking = parking;
    } catch (e) {
      ErrorMessages.logTechnical('parkingDetail', e);
      // Keep the passed-in object as a fallback; only surface the error when
      // there is nothing to render.
      if (parking == null) _loadError = 'Could not load this parking.';
    }

    // Opened without a cached listing: the vehicle was unknown on the first
    // read, so pick one now and re-read with it to get the real fit verdict.
    if (_selectedVehicle == null && parking != null) {
      _selectedVehicle = _firstCompatible(parking);
      if (_selectedVehicle != null) {
        try {
          parking = await _fetch();
          _parking = parking;
        } catch (e) {
          ErrorMessages.logTechnical('parkingDetailVehicle', e);
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Reads the listing for the selected vehicle + date window so the server adds
  /// the slot list AND per-slot availability for those real dimensions.
  Future<ParkingListing> _fetch() {
    final auth = context.read<AuthProvider>();
    return _service.getById(
      widget.parkingId,
      token: auth.accessToken ?? '',
      vehicleId: _selectedVehicle?.id,
      startDate: _start,
      endDate: _end,
    );
  }

  /// Re-reads the listing for the selected vehicle / dates so the server can
  /// re-evaluate availability. The previous snapshot stays on screen while this
  /// runs.
  Future<void> _refreshAvailability() async {
    setState(() => _refreshing = true);
    try {
      final p = await _fetch();
      if (mounted) setState(() => _parking = p);
    } catch (e) {
      // Availability here is a preview only: the booking screen re-checks it
      // authoritatively, so a failed probe just keeps the previous snapshot.
      ErrorMessages.logTechnical('parkingAvailability', e);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Lets the user pick the dates the availability is judged against. Without
  /// this the screen could only ever show one arbitrary window, and a slot
  /// booked in November would look permanently gone.
  Future<void> _pickWindow() async {
    final first = _today();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: first.add(const Duration(days: 365 * 3)),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      helpText: 'Check availability for these dates',
      saveText: 'Check',
    );
    if (picked == null) return;
    setState(() => _start = picked.start);
    await _refreshAvailability();
  }

  /// Vehicles the listing actually has slots for. The slot list decides — a car
  /// is never offered on a bike-only parking.
  List<Vehicle> _compatibleVehicles(List<Vehicle> all, ParkingListing? p) {
    if (p == null) return all;
    if (p.spaces.isEmpty) {
      return all
          .where(
            (v) => FitCheckService.vehicleAllowed(p.vehicleType, v.vehicleType),
          )
          .toList(growable: false);
    }
    return all
        .where(
          (v) => v.vehicleType == 'BIKE'
              ? p.totalBikeSpaces > 0
              : p.totalCarSpaces > 0,
        )
        .toList(growable: false);
  }

  Vehicle? _firstCompatible(ParkingListing? p) {
    final vehicles = context.read<VehicleProvider>().vehicles;
    if (p == null) return null;
    for (final v in vehicles) {
      if (FitCheckService.vehicleAllowed(p.vehicleType, v.vehicleType)) {
        return v;
      }
    }
    return vehicles.isNotEmpty ? vehicles.first : null;
  }

  /// The booking verdict for [vehicle] on the checked window.
  ///
  /// [canBook] is deliberately NOT "totalCarSpaces > 0": a slot can exist and
  /// still be taken (or too small / behind a tight gate), and in that case the
  /// user must not be able to continue to the booking form.
  ({bool canBook, String label, String? message}) _verdict(
    ParkingListing? p,
    Vehicle? vehicle,
  ) {
    if (vehicle == null) {
      return (
        canBook: false,
        label: 'Add a vehicle to book',
        message: 'Add your vehicle in the Vehicles tab first.',
      );
    }
    if (p == null) {
      return (canBook: false, label: 'Book This Parking', message: null);
    }

    final isBike = vehicle.vehicleType == 'BIKE';
    final pool = isBike ? p.bikeSpaces : p.carSpaces;
    final availability = p.availability;

    // A slot is bookable only when the server said so for THIS vehicle on THIS
    // window — that single flag already includes the fit check and the gate.
    final bookable = pool.where((s) => s.available == true).length;

    // No verdict at all (server had no vehicle, or a pre-slot listing): we
    // cannot claim it is full, so the button stays enabled and the booking
    // screen's own re-check is the authority.
    final hasVerdict =
        availability?.hasVerdict == true ||
        pool.any((s) => s.available != null);
    if (!hasVerdict) {
      if (pool.isEmpty && p.spaces.isNotEmpty) {
        return (
          canBook: false,
          label: '${isBike ? 'Bike' : 'Car'} Parking Full',
          message: ErrorMessages.noSpacesAvailable,
        );
      }
      return (canBook: true, label: 'Book This Parking', message: null);
    }

    if (bookable > 0) {
      return (canBook: true, label: 'Book This Parking', message: null);
    }

    // Nothing free for this vehicle type. Distinguish "all taken" from
    // "none of them is big enough / reachable".
    final fitsAnywhere = availability?.fitsAnySpace ?? false;
    if (!fitsAnywhere) {
      return (
        canBook: false,
        label: 'No Suitable Space',
        message: ErrorMessages.noSuitableSpace,
      );
    }
    return (
      canBook: false,
      label: '${isBike ? 'Bike' : 'Car'} Parking Full',
      message: availability?.legacyParkingBlocked == true
          ? ErrorMessages.dateConflict
          : ErrorMessages.parkingFull(vehicle.vehicleType),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parking = _parking;
    final vehicles = context.watch<VehicleProvider>().vehicles;
    final compatible = _compatibleVehicles(vehicles, parking);
    // Never leave the dropdown pointing at a vehicle this parking has no slot
    // for (e.g. after the owner removed its last bike space).
    final selected =
        (compatible.contains(_selectedVehicle) ? _selectedVehicle : null) ??
        (compatible.isNotEmpty ? compatible.first : null);
    final verdict = _verdict(parking, selected);

    return Scaffold(
      appBar: AppBar(title: const Text('Parking details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : parking == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_loadError ?? 'Could not load this parking.'),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() => _loading = true);
                      _init().then((_) {
                        if (mounted) setState(() => _loading = false);
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : ConstrainedContent(
              maxWidth: ResponsiveLayout.contentMaxWidth,
              child: _build(parking, compatible, selected),
            ),
      bottomNavigationBar: parking == null
          ? null
          : SafeArea(
              child: ConstrainedContent(
                maxWidth: ResponsiveLayout.formMaxWidth,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected != null && verdict.message != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            verdict.message!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ),
                      PrimaryButton(
                        label: verdict.label,
                        icon: verdict.canBook
                            ? Icons.calendar_month_outlined
                            : Icons.do_not_disturb_on_outlined,
                        // A disabled button is grey, and pressing it is
                        // impossible — so "full" can never navigate to the form.
                        disabledBackgroundColor: verdict.canBook
                            ? null
                            : AppColors.disabled,
                        onPressed: verdict.canBook
                            ? () {
                                Navigator.of(context).pushNamed(
                                  AppRoutes.booking,
                                  arguments: {'parking': parking},
                                );
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _build(
    ParkingListing p,
    List<Vehicle> compatible,
    Vehicle? selectedVehicle,
  ) {
    final fit = _computeFit(p, selectedVehicle);

    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        // Photo pager (REAL photos from the DB). Height scales with screen
        // width but never goes below the phone value (220), so detail photos
        // look right from a small phone to a desktop window.
        SizedBox(
          height: (MediaQuery.sizeOf(context).width * 0.45)
              .clamp(220.0, 340.0)
              .toDouble(),
          child: p.photoUrls.isEmpty
              ? Container(
                  color: AppColors.userPrimaryLight,
                  child: const Icon(
                    Icons.local_parking,
                    size: 72,
                    color: AppColors.userPrimary,
                  ),
                )
              : Stack(
                  children: [
                    PageView.builder(
                      itemCount: p.photoUrls.length,
                      onPageChanged: (i) => setState(() => _photoIndex = i),
                      itemBuilder: (_, i) => Image.network(
                        p.photoUrls[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.userPrimaryLight,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    if (p.photoUrls.length > 1)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_photoIndex + 1}/${p.photoUrls.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      p.parkingName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (p.distanceKm != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.userPrimaryLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        Helpers.formatDistance(p.distanceKm! * 1000),
                        style: const TextStyle(
                          color: AppColors.userPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.place_outlined,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      p.address,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Vehicle to check availability against. Every number below is
              // computed server-side for this vehicle's real dimensions.
              if (compatible.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.directions_car_outlined,
                        size: 18,
                        color: AppColors.userPrimary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Check for',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButton<Vehicle>(
                          value: selectedVehicle,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          isDense: true,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          items: [
                            for (final v in compatible)
                              DropdownMenuItem(
                                value: v,
                                child: Text(
                                  v.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            setState(() => _selectedVehicle = v);
                            _refreshAvailability();
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              // The dates the availability below is judged against. It has to be
              // visible AND editable: without it a slot booked in November
              // would look permanently gone, and "1 of 3 free" would be a
              // snapshot with no context.
              _dateWindowRow(),

              // Slot availability for the selected vehicle — the numbers the
              // server computed, never a hardcoded count.
              if (p.availability != null || p.totalSpaces > 0)
                _spacesCard(p, selectedVehicle),

              const SizedBox(height: 16),
              _fitSection(p, fit, selectedVehicle),

              const SizedBox(height: 16),
              _infoCard(
                'Dimensions',
                children: [
                  _row(
                    'Parking size',
                    '${Helpers.feetLabel(p.lengthM)} × '
                        '${Helpers.feetLabel(p.widthM)} × '
                        '${Helpers.feetLabel(p.heightM)}',
                  ),
                  if (p.entranceLengthM != null ||
                      p.entranceWidthM != null ||
                      p.entranceHeightM != null)
                    _row(
                      'Entrance size',
                      '${Helpers.feetLabel(p.entranceLengthM)} × '
                          '${Helpers.feetLabel(p.entranceWidthM)} × '
                          '${Helpers.feetLabel(p.entranceHeightM)}',
                    ),
                ],
              ),

              const SizedBox(height: 12),
              // Plans are per vehicle type — show the ones the selected
              // vehicle can actually book.
              Builder(
                builder: (context) {
                  final plan = _detailPlan(p, selectedVehicle);
                  return _infoCard(
                    'Rental',
                    children: [
                      if (plan.monthlyEnabled)
                        _row(
                          'Monthly',
                          Helpers.formatRupees(plan.monthlyRent ?? 0),
                        ),
                      if (plan.yearlyEnabled)
                        _row(
                          'Yearly',
                          Helpers.formatRupees(plan.yearlyRent ?? 0),
                        ),
                      _row('Access hours', p.accessHours),
                      _row(
                        'Parking spaces',
                        '${p.totalCarSpaces} car · ${p.totalBikeSpaces} bike',
                      ),
                      if (p.allowMixedParking) _row('Mixed parking', 'Allowed'),
                    ],
                  );
                },
              ),

              if (p.amenities.isNotEmpty) ...[
                const SizedBox(height: 12),
                _infoCard(
                  'Amenities',
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final a in p.amenities)
                          Chip(
                            label: Text(
                              a,
                              style: const TextStyle(fontSize: 12),
                            ),
                            avatar: const Icon(
                              Icons.check,
                              size: 15,
                              color: AppColors.success,
                            ),
                            backgroundColor: AppColors.success.withValues(
                              alpha: 0.06,
                            ),
                            side: BorderSide.none,
                          ),
                      ],
                    ),
                  ],
                ),
              ],

              if (p.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                _infoCard('Description', children: [Text(p.description)]),
              ],
              if (p.conditions.isNotEmpty) ...[
                const SizedBox(height: 12),
                _infoCard('Conditions', children: [Text(p.conditions)]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _fitSection(ParkingListing p, FitResult? fit, Vehicle? vehicle) {
    if (fit == null) {
      return _infoCard(
        'Your vehicle',
        children: const [
          Text(
            'Add a vehicle in the Vehicles tab to check if your ride fits.',
            style: TextStyle(fontSize: 13),
          ),
        ],
      );
    }

    final (Color color, IconData icon) = switch (fit) {
      FitResult.fit => (AppColors.success, Icons.check_circle),
      FitResult.tightFit => (AppColors.warning, Icons.error_outline),
      FitResult.doesNotFit => (AppColors.error, Icons.cancel_outlined),
    };
    final v = vehicle;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      fit.label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (v != null)
                      Expanded(
                        child: Text(
                          v.displayName,
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (v != null)
                  Text(
                    'L ${Helpers.feetLabel(v.lengthM)} × W '
                    '${Helpers.feetLabel(v.widthM)} × H '
                    '${Helpers.feetLabel(v.heightM)} vs parking '
                    'L ${Helpers.feetLabel(p.lengthM)} × W '
                    '${Helpers.feetLabel(p.widthM)} × H '
                    '${Helpers.feetLabel(p.heightM)} '
                    '(+1.64/+0.98/+0.49 ft clearance)',
                    style: const TextStyle(fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The rental plan that applies to the vehicle picked on this screen (or
  /// either type's plan when nothing is picked yet).
  RentPlan _detailPlan(ParkingListing p, Vehicle? v) =>
      p.planFor(v?.vehicleType);

  FitResult? _computeFit(ParkingListing p, Vehicle? v) {
    if (v == null) return null;
    final pLen = p.lengthM;
    final pWid = p.widthM;
    final pHgt = p.heightM;
    if (pLen == null || pWid == null || pHgt == null) return null;
    if (v.lengthM == null || v.widthM == null || v.heightM == null) {
      return null;
    }
    if (!FitCheckService.vehicleAllowed(p.vehicleType, v.vehicleType)) {
      return null;
    }
    return FitCheckService.check(
      parkingLengthM: pLen,
      parkingWidthM: pWid,
      parkingHeightM: pHgt,
      vehicleLengthM: v.lengthM!,
      vehicleWidthM: v.widthM!,
      vehicleHeightM: v.heightM!,
    );
  }

  /// The date window every number on this screen describes, and the only way
  /// to change it. Tapping re-runs the server query for the new range, so the
  /// counts, the greyed slots and the button can never describe stale dates.
  Widget _dateWindowRow() {
    final label = '${Helpers.formatDate(_start)} – ${Helpers.formatDate(_end)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _refreshing ? null : _pickWindow,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.event_available_outlined,
                size: 18,
                color: AppColors.userPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Availability for',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.edit_calendar_outlined,
                size: 18,
                color: AppColors.userPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The parking-spaces card: a per-vehicle-type free/total summary with the
  /// user's own vehicle type highlighted, plus the real slot rows when the
  /// server returned them. A "2 of 3 available" reads as one booked space, not
  /// a dead listing.
  Widget _spacesCard(ParkingListing p, Vehicle? vehicle) {
    final a = p.availability;
    final isBike = vehicle?.vehicleType == 'BIKE';
    var carFree = a?.carSpaces.available;
    var carTotal = a?.carSpaces.total ?? p.totalCarSpaces;
    var bikeFree = a?.bikeSpaces.available;
    var bikeTotal = a?.bikeSpaces.total ?? p.totalBikeSpaces;

    // The highlighted tile is the user's own vehicle type, so it must count the
    // slots THAT vehicle can actually use — the same numbers the button and the
    // server's status line are built from. Otherwise the card could read "3 of 3
    // available" while one of the three sits greyed out as "Unavailable" purely
    // because it is too small. The other type keeps the date-only pool, which
    // is all that can honestly be said without a vehicle of that type.
    final verdict = a != null && a.hasVerdict ? a : null;
    if (verdict != null) {
      if (verdict.vehicleType == ParkingSpaceVehicleType.bike) {
        bikeFree = verdict.availableSpaces;
        bikeTotal = verdict.totalSpaces;
      } else {
        carFree = verdict.availableSpaces;
        carTotal = verdict.totalSpaces;
      }
    }

    Widget tile(String label, int? free, int total, bool highlight) {
      final known = free != null;
      // Every slot of this type is gone for the checked window. Greyed, not
      // hidden, so the user sees a real listing that simply is not free.
      final isFull = known && free == 0 && total > 0;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: highlight ? AppColors.userPrimaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight ? AppColors.userPrimary : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                known ? '$free of $total available' : '$total total',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  // Full reads as muted/grey; a live number stays black.
                  color: isFull
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final slots = p.spaces;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Parking spaces',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              if (_refreshing)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.userPrimary,
                  ),
                ),
            ],
          ),
          if (carTotal == 0 && bikeTotal == 0) ...[
            const SizedBox(height: 6),
            const Text(
              'This parking has no individual parking spaces yet.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              children: [
                tile('Car spaces', carFree, carTotal, !isBike && carTotal > 0),
                const SizedBox(width: 10),
                tile(
                  'Bike spaces',
                  bikeFree,
                  bikeTotal,
                  isBike && bikeTotal > 0,
                ),
              ],
            ),
            // The server's own sentence, so "Car Parking Full" and "your
            // vehicle may not fit" always come from one source of truth.
            if (a != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: (a.isAvailable ? AppColors.success : AppColors.warning)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      a.isAvailable
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: 16,
                      color: a.isAvailable
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.statusLine,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: a.isAvailable
                              ? AppColors.success
                              : AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // The individual slots, so "1 of 3 free" is never a mystery. A
            // slot is only listed as free when the server said so for THIS
            // vehicle — otherwise a bike slot is never offered to a car.
            if (slots.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in slots)
                    _slotChip(
                      s,
                      isUserType: s.vehicleType == vehicle?.vehicleType,
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// One parking-space chip. Booked slots are shown GREYED OUT, never removed:
  /// the user has to be able to see that the space exists and that somebody
  /// else has it, otherwise "1 of 3 available" is a mystery.
  ///
  /// The reason comes from the server's factual `booked` flag, which is
  /// date-only (an occupying booking overlaps the checked window). When it is
  /// false the slot is greyed for a different reason — the vehicle does not fit
  /// it, or the gate is too tight — so the copy says "Unavailable" instead of
  /// blaming an absent booking.
  ///
  /// `available == null` means the server did not evaluate this slot for the
  /// current vehicle, so it renders neutral rather than guessing.
  Widget _slotChip(ParkingSpace s, {required bool isUserType}) {
    final free = s.available;
    final (Color fg, Color bg, IconData icon) = switch (free) {
      true => (
        AppColors.success,
        AppColors.successLight,
        Icons.check_circle_outline,
      ),
      // Grey, not amber/red: an occupied slot is a normal fact of the listing,
      // not an error the user has to act on.
      false => (
        AppColors.textSecondary,
        AppColors.disabled,
        s.booked == true ? Icons.event_busy : Icons.do_not_disturb_on_outlined,
      ),
      null => (
        AppColors.textSecondary,
        AppColors.disabled,
        Icons.remove_circle_outline,
      ),
    };
    final state = switch (free) {
      true => null,
      false => s.booked == true ? 'Booked' : 'Unavailable',
      null => 'Unknown',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isUserType && free == true
              ? AppColors.userPrimary
              : AppColors.border,
          width: isUserType && free == true ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            s.isBike ? Icons.two_wheeler : Icons.directions_car,
            size: 13,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            s.displayLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
          if (state != null) ...[
            const SizedBox(width: 4),
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
            Text(
              state,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
          if (s.dimensionLabel != '—') ...[
            const SizedBox(width: 5),
            Text(
              s.dimensionLabel,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard(String title, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
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
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
