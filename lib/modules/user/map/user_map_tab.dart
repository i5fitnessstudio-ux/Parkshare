import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/location_defaults.dart';
import '../../../core/constants/map_tiles.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/services/location_search_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/utils/helpers.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../modules/shared/providers/location_provider.dart';
import '../../../modules/user/providers/user_map_provider.dart';
import '../../../modules/vehicle/providers/vehicle_provider.dart';
import '../../../shared/models/parking.dart';
import '../../../shared/models/vehicle.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';

/// Rapido-style vehicle-user map: search bar, real GPS permission handling
/// (no crash paths), searched-location override until "Current Location",
/// real green P markers from the backend, ~600 ms pan debounce and a preview
/// card for the selected parking.
///
/// Location priority: real GPS -> last known fix -> Tamil Nadu (Chennai)
/// fallback. The map never opens on a foreign coordinate: the first frame is
/// already centred on the Tamil Nadu fallback and is replaced as soon as a
/// real fix arrives.
class UserMapTab extends StatefulWidget {
  /// True when the Map tab is the visible tab. The map stays mounted in the
  /// parent `IndexedStack`, so the location permission prompt and the first
  /// GPS read are deferred until the user actually opens this tab.
  final bool active;

  const UserMapTab({super.key, this.active = true});

  @override
  State<UserMapTab> createState() => _UserMapTabState();
}

class _UserMapTabState extends State<UserMapTab> {
  final MapController _mapController = MapController();
  final LocationSearchService _search = LocationSearchService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  static const double _kZoom = 16;
  static const double _kSearchZoom = 17;
  static const LatLng _fallbackCenter = LatLng(
    LocationDefaults.latitude,
    LocationDefaults.longitude,
  ); // Tamil Nadu (Chennai)
  static const double _nearbyRadiusKm = 5;

  List<PlaceSearchResult> _suggestions = [];
  bool _initializing = true;
  bool _locating = false;

  // Debounce + sequence guard for the search field so we don't fire a
  // geocode request on every keystroke and stale responses can't overwrite
  // newer ones.
  static const Duration _searchDebounceTime = Duration(milliseconds: 350);
  Timer? _searchDebounce;
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    }
  }

  @override
  void didUpdateWidget(covariant UserMapTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active || !widget.active) return;
    // Opened the Map tab.
    if (_initializing) {
      // First time: ask for permission and resolve the position.
      WidgetsBinding.instance.addPostFrameCallback((_) => _init());
      return;
    }
    // Already initialised (the user came back from Vehicles/Inbox/Bookings,
    // possibly after editing a vehicle): the saved dimensions may have changed,
    // so the marker availability is recomputed for the vehicle as it is now.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshForVehicle());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The vehicle the map filters availability against. The user's first saved
  /// vehicle is used so markers are immediately meaningful; the chip below
  /// switches it. Never fabricated — only a real saved vehicle is used.
  Vehicle? get _activeVehicle {
    final vehicles = context.read<VehicleProvider>().vehicles;
    final map = context.read<UserMapProvider>();
    for (final v in vehicles) {
      if (v.id == map.activeVehicleId) return v;
    }
    return vehicles.isEmpty ? null : vehicles.first;
  }

  Future<void> _init() async {
    if (!mounted) return;
    final loc = context.read<LocationProvider>();
    final map = context.read<UserMapProvider>();
    final auth = context.read<AuthProvider>();
    map.token = auth.accessToken ?? '';

    // Point the map at a real saved vehicle so the server evaluates slot
    // availability for that vehicle's actual dimensions.
    final vehicle = _activeVehicle;
    map.setActiveVehicle(vehicle?.id, vehicle?.vehicleType);

    setState(() => _locating = true);

    // Request permission gracefully; never crash on denial/disable. A cached
    // fix short-circuits, so this neither re-prompts nor re-hits the GPS.
    await loc.refresh();
    if (!mounted) return;

    // Centre on the real GPS fix when available, otherwise keep the Tamil
    // Nadu fallback - markers still work without GPS.
    final point = loc.point;
    final center = LatLng(
      point?.latitude ?? _fallbackCenter.latitude,
      point?.longitude ?? _fallbackCenter.longitude,
    );
    _mapController.move(center, _kZoom);
    if (!mounted) return;
    setState(() {
      _locating = false;
      _initializing = false;
    });

    await map.loadNearby(
      lat: center.latitude,
      lng: center.longitude,
      radiusKm: _nearbyRadiusKm,
    );
  }

  /// Re-runs the nearby query for the vehicle as it is saved RIGHT NOW.
  ///
  /// Used when the Map tab is re-opened after the first visit: "Save & Find
  /// Parking" can change a vehicle's dimensions without changing its id or
  /// type, and the server scores slot availability from those real dimensions,
  /// so the markers must be recomputed instead of showing the previous answer.
  Future<void> _refreshForVehicle() async {
    if (!mounted) return;
    final map = context.read<UserMapProvider>();
    final auth = context.read<AuthProvider>();
    map.token = auth.accessToken ?? '';
    final vehicle = _activeVehicle;
    await map.setActiveVehicle(vehicle?.id, vehicle?.vehicleType, force: true);
  }

  void _onMapEvent(MapEvent event) {
    // Ignore the settle events fired during `_init` (first mount / size
    // changes): they race with the explicit GPS centred `loadNearby` and would
    // re-fetch around the fallback centre. Only user moves (drag end) refresh.
    if (event is MapEventMoveEnd && !_initializing) {
      final c = event.camera.center;
      context.read<UserMapProvider>().onCameraSettled(
        lat: c.latitude,
        lng: c.longitude,
      );
    }
  }

  Future<void> _onSearchChanged(String query) async {
    final seq = ++_searchSeq;
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (mounted) setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(_searchDebounceTime, () async {
      final results = await _search.search(trimmed);
      if (!mounted || seq != _searchSeq) return;
      setState(() => _suggestions = results);
    });
  }

  Future<void> _onSuggestionTap(PlaceSearchResult place) async {
    await _applySearchResult(place);
  }

  /// Keyboard "search" action: geocode the EXACT typed address and move the
  /// camera there (with nearby parking refreshed around the result).
  Future<void> _onSearchSubmitted() async {
    _searchSeq++; // invalidate any in-flight suggestion search
    _searchDebounce?.cancel();
    final query = _searchController.text;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      if (mounted) setState(() => _suggestions = []);
      return;
    }
    _searchFocus.unfocus();
    final result = await _search.geocodeAddress(trimmed);
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location not found. Please enter a more complete address.',
          ),
        ),
      );
      return;
    }
    await _applySearchResult(result);
  }

  Future<void> _applySearchResult(PlaceSearchResult place) async {
    _searchSeq++; // invalidate any in-flight search
    _searchDebounce?.cancel();
    _searchController.text = place.name;
    setState(() => _suggestions = []);
    _searchFocus.unfocus();
    final map = context.read<UserMapProvider>();
    // Search overrides GPS and re-queries nearby owner parkings around the
    // searched coordinate (existing provider path).
    await map.searchAndCenter(place);
    if (!mounted) return;
    _mapController.move(LatLng(place.latitude, place.longitude), _kSearchZoom);
  }

  /// The blue "current location" button: services -> permission -> fresh fix
  /// -> move the map there -> refresh nearby parking. Never leaves the map
  /// stuck on a previous coordinate and never freezes the whole map.
  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    final loc = context.read<LocationProvider>();
    final map = context.read<UserMapProvider>();
    setState(() => _locating = true);
    try {
      // force: the user explicitly asked for a fresh fix.
      await loc.refresh(force: true);
      final point = loc.point;
      if (!mounted) return;
      if (point == null) {
        // No fix (denied / services off / timeout): stay where we are and let
        // the banner explain why, with retry + settings.
        setState(() => _locating = false);
        return;
      }
      _searchController.clear();
      await map.backToGps();
      _mapController.move(LatLng(point.latitude, point.longitude), _kZoom);
      setState(() => _locating = false);
      await map.loadNearby(
        lat: point.latitude,
        lng: point.longitude,
        radiusKm: _nearbyRadiusKm,
      );
    } catch (e) {
      ErrorMessages.logTechnical('currentLocation', e);
      if (!mounted) return;
      setState(() => _locating = false);
      _toast(ErrorMessages.locationUnavailable);
    }
  }

  Future<void> _retryLocation() async => _useCurrentLocation();

  Future<void> _openSettings(LocationAccess access) async {
    final loc = context.read<LocationProvider>();
    if (access == LocationAccess.disabled) {
      await loc.openLocationSettings();
    } else {
      await loc.openAppSettings();
    }
  }

  /// Switches the vehicle the map evaluates slot availability against. The
  /// provider re-queries the current viewport, so the marker state is always
  /// the backend's answer for that vehicle — never a client-side guess.
  Future<void> _selectVehicle(List<Vehicle> vehicles, String id) async {
    final v = vehicles.where((e) => e.id == id).firstOrNull;
    if (v == null) return;
    await context.read<UserMapProvider>().setActiveVehicle(v.id, v.vehicleType);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Canonical permission copy. Kept in one place so the banner and the
  /// provider can never drift apart.
  static String _bannerMessageFor(LocationAccess access) => switch (access) {
    LocationAccess.denied => ErrorMessages.locationPermission,
    LocationAccess.disabled => ErrorMessages.locationServicesOff,
    LocationAccess.granted => ErrorMessages.locationUnavailable,
    LocationAccess.unavailable => ErrorMessages.locationUnavailable,
  };

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocationProvider>();
    final map = context.watch<UserMapProvider>();
    final vehicles = context.watch<VehicleProvider>().vehicles;

    // Graceful permission states (never a crash).
    final access = loc.access;
    final gpsPoint = loc.point;
    final showBanner = !_initializing && !_locating && gpsPoint == null;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _fallbackCenter,
            initialZoom: _kZoom,
            onMapEvent: _onMapEvent,
          ),
          children: [
            // Satellite imagery: this is the tile layer only. The camera,
            // the marker layer below and every gesture above/below it are
            // untouched, so switching the raster source cannot move a marker,
            // break the search or disturb the current-location logic.
            MapTiles.satellite(),
            MarkerLayer(
              markers: [
                // The user's own position: ALWAYS blue, never a parking green.
                if (gpsPoint != null)
                  Marker(
                    point: LatLng(gpsPoint.latitude, gpsPoint.longitude),
                    width: 26,
                    height: 26,
                    child: _CurrentLocationDot(accurate: loc.hasFix),
                  ),
                // REAL parking markers from the backend (green P). A parking
                // whose matching slots are all taken is greyed, not hidden —
                // one booked slot must never make a property disappear.
                for (final p in map.nearby)
                  if (p.latitude != null && p.longitude != null)
                    _parkingMarker(
                      parking: p,
                      selected: map.selected?.id == p.id,
                      onTap: () => map.select(p),
                    ),
              ],
            ),
            // Attribution for the satellite tiles. Anchored to the bottom
            // corner of the map, so it can never sit under the search /
            // current-location row at the top or under the Scaffold's bottom
            // navigation bar (which lives outside the FlutterMap).
            MapTiles.satelliteCredit(),
          ],
        ),

        // Search + current location row: full width on phones, capped at
        // overlay width on tablets/desktop so the controls never span the
        // whole window.
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12,
          width: context.isTabletOrWider
              ? ResponsiveLayout.mapOverlayMaxWidth
              : null,
          right: context.isTabletOrWider ? null : 12,
          child: Column(
            children: [
              Material(
                color: AppColors.surface,
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.search,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          onChanged: _onSearchChanged,
                          onSubmitted: (_) => _onSearchSubmitted(),
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            hintText: 'Search area or landmark',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      // Vehicle switcher: re-runs the nearby query so the
                      // markers reflect THIS vehicle's real slot needs.
                      if (vehicles.length > 1)
                        PopupMenuButton<String>(
                          tooltip: 'Vehicle for availability',
                          position: PopupMenuPosition.under,
                          onSelected: (id) => _selectVehicle(vehicles, id),
                          itemBuilder: (context) => [
                            for (final v in vehicles)
                              PopupMenuItem<String>(
                                value: v.id,
                                child: Row(
                                  children: [
                                    Icon(
                                      v.vehicleType == 'BIKE'
                                          ? Icons.two_wheeler_outlined
                                          : Icons.directions_car_outlined,
                                      size: 18,
                                      color: map.activeVehicleId == v.id
                                          ? AppColors.userPrimary
                                          : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        v.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight:
                                              map.activeVehicleId == v.id
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              Icons.directions_car_filled_outlined,
                              color: AppColors.userPrimary,
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Use current location',
                        onPressed: _locating ? null : _useCurrentLocation,
                        icon: const Icon(
                          Icons.my_location,
                          color: AppColors.currentLocationBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Search suggestions (Material so ListTile ink splashes render).
              if (_suggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Material(
                    color: AppColors.surface,
                    elevation: 2,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    // Cap + internal scroll so a long suggestion list can
                    // never push the cluster past the bottom of the map.
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final s in _suggestions)
                            ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.place_outlined,
                                color: AppColors.userPrimary,
                                size: 20,
                              ),
                              title: Text(
                                s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: s.address != null
                                  ? Text(
                                      s.address!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    )
                                  : null,
                              onTap: () => _onSuggestionTap(s),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_locating)
                const _StatusPill(
                  icon: Icons.my_location,
                  text: 'Getting location...',
                ),
              // Nearby fetch failed: friendly message + Retry (never a crash
              // path, never a technical message).
              if (!_locating &&
                  _suggestions.isEmpty &&
                  map.phase == NearbyPhase.error)
                _StatusPill(
                  icon: Icons.wifi_off_rounded,
                  text: map.error ?? ErrorMessages.nearbyFailed,
                  actionLabel: 'Retry',
                  onAction: map.retry,
                ),
              if (showBanner && _suggestions.isEmpty)
                _PermissionBanner(
                  access: access,
                  permissionPermanentlyDenied: loc.permissionPermanentlyDenied,
                  message: loc.errorMessage ?? _bannerMessageFor(access),
                  onRetry: _retryLocation,
                  onOpenSettings: () => _openSettings(access),
                ),
              // Empty state (only after the request really finished with no
              // rows). Sits inside the search-cluster column so it is always
              // positioned right under the search bar on every screen size.
              if (map.isEmpty &&
                  !showBanner &&
                  !_locating &&
                  map.phase == NearbyPhase.empty &&
                  _suggestions.isEmpty &&
                  !_initializing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Color(0x220F172A), blurRadius: 6),
                        ],
                      ),
                      child: Text(
                        map.activeVehicleType == 'BIKE'
                            ? 'No bike parking spaces available nearby'
                            : 'No car parking spaces available nearby',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Preview card for the selected parking: full width on phones, capped at
        // overlay width bottom-left on tablets/desktop.
        if (map.selected != null)
          Positioned(
            left: 12,
            bottom: 12,
            width: context.isTabletOrWider
                ? ResponsiveLayout.mapOverlayMaxWidth
                : null,
            right: context.isTabletOrWider ? null : 12,
            child: _ParkingPreviewCard(
              parking: map.selected!,
              onView: () {
                final p = map.selected!;
                map.select(null);
                Navigator.of(context).pushNamed(
                  AppRoutes.parkingDetail,
                  arguments: {'parkingId': p.id, 'parking': p},
                );
              },
              onClose: () => map.select(null),
            ),
          ),
      ],
    );
  }
}

/// A real parking marker. Green "P" while the active vehicle still has a free
/// slot, a plain grey circle (no glyph at all) when every matching slot is
/// taken, and "×" when this listing has no slot of the vehicle's type at all.
/// The state is always the server's own `availability` block — never a
/// client-side guess. Full is only shown for a vehicle whose type has slots, so
/// a bike-only listing is never greyed out for a car user (it simply has no
/// bike slot to fill).
Marker _parkingMarker({
  required ParkingListing parking,
  required bool selected,
  required VoidCallback onTap,
}) {
  final a = parking.availability;
  // No availability block, or one built without a vehicle, carries no verdict
  // for this user — the marker stays green rather than guessing.
  final known = a != null && a.vehicleType != null;
  final free = !known || a.isAvailable;
  // totalSpaces == 0 with a known type means the listing has no slot of that
  // type at all (a car on a bike-only lot), which is different from "full".
  final noSuchType = known && a.totalSpaces == 0;
  final full = known && !free && a.fitsAnySpace;

  final Color fill;
  if (selected) {
    fill = AppColors.parkingMarkerGreenDark;
  } else if (!free) {
    fill = AppColors.textHint;
  } else {
    fill = AppColors.parkingMarkerGreen;
  }

  return Marker(
    point: LatLng(parking.latitude!, parking.longitude!),
    width: 42,
    height: 42,
    alignment: Alignment.topCenter,
    child: GestureDetector(
      key: const Key('parking-marker'),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.userPrimary : Colors.white,
            width: selected ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: (selected ? AppColors.userPrimary : fill).withValues(
                alpha: 0.34,
              ),
              blurRadius: 8,
            ),
          ],
        ),
        alignment: Alignment.center,
        // One glyph carries the state: "x" when the listing has no slot of the
        // vehicle's type, "P" while a matching slot is still free. A taken
        // listing stays a plain grey circle — no "!", no symbol at all.
        child: noSuchType
            ? Text(
                '×',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              )
            : (full
                  ? const SizedBox.shrink()
                  : Text(
                      'P',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    )),
      ),
    ),
  );
}

/// The user's own position marker. Always blue (never a parking green) with a
/// white ring and a soft blue halo so it stays readable over satellite tiles.
class _CurrentLocationDot extends StatelessWidget {
  const _CurrentLocationDot({required this.accurate});

  /// A low-accuracy fix (emulator / indoor) gets a translucent halo.
  final bool accurate;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('current-location-marker'),
      decoration: BoxDecoration(
        color: AppColors.currentLocationBlue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: AppColors.currentLocationBlue.withValues(
              alpha: accurate ? 0.44 : 0.18,
            ),
            blurRadius: accurate ? 10 : 16,
            spreadRadius: accurate ? 1 : 4,
          ),
        ],
      ),
    );
  }
}

/// Small inline pill used for "Getting location…" / nearby-fetch errors. It
/// never shows a technical message and always offers a way forward.
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x220F172A), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.currentLocationBlue, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.userPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  final LocationAccess access;
  final bool permissionPermanentlyDenied;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  const _PermissionBanner({
    required this.access,
    required this.permissionPermanentlyDenied,
    required this.message,
    required this.onRetry,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (access) {
      LocationAccess.denied => Icons.location_off_outlined,
      LocationAccess.disabled => Icons.location_disabled_outlined,
      _ => Icons.location_searching_outlined,
    };
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x220F172A), blurRadius: 6)],
      ),
      // The message sits on its own line above the actions: a single Row with
      // icon + message + two buttons left the copy squeezed to a few characters
      // and could overflow on narrow screens.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.warning, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          // Retry always; Settings is the escape hatch once the system dialog
          // has stopped appearing for good ("don't ask again"), where a bare
          // re-request would just be a no-op.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.userPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry'),
              ),
              if (permissionPermanentlyDenied)
                TextButton(
                  onPressed: onOpenSettings,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.userPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Settings'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParkingPreviewCard extends StatelessWidget {
  final ParkingListing parking;
  final VoidCallback onView;
  final VoidCallback onClose;

  const _ParkingPreviewCard({
    required this.parking,
    required this.onView,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child:
                    parking.thumbnailUrl != null &&
                        parking.thumbnailUrl!.isNotEmpty
                    ? Image.network(
                        parking.thumbnailUrl!,
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
                    parking.parkingName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (parking.distanceKm != null)
                        Text(
                          Helpers.formatDistance(parking.distanceKm! * 1000),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.userPrimary,
                          ),
                        ),
                      if (parking.cheapestRent != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          Helpers.formatRupees(parking.cheapestRent!),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ownerPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Availability: the server's own slot counts for the active
                  // vehicle, plus the legacy "next free date" hint.
                  if (parking.availability != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      parking.availability!.statusLine,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: parking.availability!.isAvailable
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (parking.currentBooking != null &&
                      parking.availableFrom != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Currently booked · free from '
                      '${_friendlyDate(parking.availableFrom!)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
                TextButton(
                  onPressed: onView,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.userPrimary,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('View →'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
    color: AppColors.userPrimaryLight,
    child: const Icon(Icons.local_parking, color: AppColors.userPrimary),
  );

  /// Formats a backend "YYYY-MM-DD" date into "23 Oct 2026".
  static String _friendlyDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    final day = int.tryParse(parts[2]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[0]);
    if (day == null || month == null || year == null) return isoDate;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = (month >= 1 && month <= 12) ? months[month - 1] : '?';
    return '$day $m $year';
  }
}
