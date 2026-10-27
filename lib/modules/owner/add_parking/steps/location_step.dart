import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/location_defaults.dart';
import '../../../../core/constants/map_tiles.dart';
import '../../../../core/services/location_search_service.dart';
import '../../../../core/services/location_service.dart';
import '../../../../modules/shared/providers/location_provider.dart';
import '../../../../shared/widgets/responsive/responsive_layout.dart';
import '../parking_draft.dart';

/// Step 3 — Pin the parking location on the map. The map centre becomes the
/// parking coordinates; the user can search a place, use their GPS position,
/// or drag the map to re-pin. Reverse-geocoded addresses are debounced so the
/// geocoder is not hammered while the map is moving.
///
/// Default anchor is Tamil Nadu (Chennai). When Step 2 collected an address
/// it is geocoded and the map opens there; a previously selected coordinate is
/// always respected and only re-geocoded when the Step-2 address changed.
class LocationStep extends StatefulWidget {
  final ParkingDraft draft;
  final VoidCallback onChanged;

  /// When false the FlutterMap is NOT mounted (the wizard index-gates this to
  /// step 2). Mounting flutter_map inside an offstage IndexedStack child makes
  /// it re-fire size-change events forever, so the map must only ever exist
  /// while the step is the visible one.
  final bool active;

  const LocationStep({
    super.key,
    required this.draft,
    required this.onChanged,
    this.active = true,
  });

  @override
  State<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<LocationStep> {
  final MapController _mapController = MapController();
  final LocationSearchService _search = LocationSearchService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// Safe fallback: Tamil Nadu (Chennai) — never an overseas default.
  static const LatLng _fallback = LatLng(
    LocationDefaults.latitude,
    LocationDefaults.longitude,
  );
  static const double _defaultZoom = 15;

  /// Address/building-level zoom used after a successful geocode.
  static const double _addressZoom = 16;
  static const Duration _searchDebounceTime = Duration(milliseconds: 400);
  static const Duration _reverseDebounceTime = Duration(milliseconds: 350);

  List<PlaceSearchResult> _suggestions = [];
  Timer? _searchDebounce;
  Timer? _reverseDebounce;
  int _searchSeq = 0;
  int _reverseSeq = 0;

  /// True while a location operation (initial seed / address geocode /
  /// current location) is applying a programmatic position. MapEventMoveEnd
  /// events fired in this window (first mount, resize, keyboard open/close)
  /// must not overwrite the applied coordinate with a stale centre.
  bool _seeding = false;

  /// The Step-2 address query that produced the CURRENT draft coordinates
  /// (whatever the source: address geocode, GPS, search, drag or current
  /// location). If it differs from the current Step-2 query on a later
  /// activation, the address changed and we re-geocode; otherwise the
  /// existing coordinate is kept so manual picks are never clobbered.
  String? _coordsQuery;

  LatLng get _initialCenter {
    final lat = widget.draft.latitude;
    final lng = widget.draft.longitude;
    if (lat != null && lng != null) return LatLng(lat, lng);
    return _fallback;
  }

  @override
  void initState() {
    super.initState();
    // No seeding here: the map is not active when the wizard opens and the
    // Step-2 fields are usually still empty.
  }

  @override
  void didUpdateWidget(covariant LocationStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameActive = widget.active && !oldWidget.active;
    if (becameActive) {
      // Gate map events BEFORE the map mounts so its first settle event
      // cannot write the fallback centre into the draft.
      _seeding = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _seedLocation();
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _reverseDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Seeding: saved coordinate -> Step-2 address -> GPS -> Tamil Nadu
  // ------------------------------------------------------------------
  Future<void> _seedLocation() async {
    if (!mounted) return;
    _seeding = true;
    try {
      final q = _buildStep2Query();
      final lat = widget.draft.latitude;
      final lng = widget.draft.longitude;

      if (lat != null && lng != null) {
        final addressChanged =
            _coordsQuery != null && _coordsQuery != q && q.isNotEmpty;
        if (addressChanged) {
          final resolved = await _geocodeAndApply(q);
          if (!resolved) {
            // New address could not be geocoded: keep the previous pick.
            _requestReverseGeoCode(LatLng(lat, lng));
          }
        } else {
          // Coordinate already selected (or unchanged address): the map just
          // remounted on it via [_initialCenter] — no camera jump.
          _requestReverseGeoCode(LatLng(lat, lng));
        }
        return;
      }

      // No coordinate yet — try the Step-2 address first.
      if (q.isNotEmpty) {
        final resolved = await _geocodeAndApply(q);
        if (resolved) return;
      }

      // Then a real GPS fix (existing "current location" plumbing).
      final gps = await _resolveGps();
      if (gps != null) {
        final target = LatLng(gps.latitude, gps.longitude);
        _setDraftLocation(target);
        _settleAt(target, zoom: _defaultZoom, reverse: true);
        return;
      }

      // Safe fallback: Tamil Nadu.
      final target = _fallback;
      _setDraftLocation(target);
      _settleAt(target, zoom: _defaultZoom, reverse: true);
    } finally {
      _seeding = false;
    }
  }

  /// Geocodes the Step-2 address and, when resolved, stores + moves to it.
  /// Returns false when it could not be resolved.
  Future<bool> _geocodeAndApply(String q) async {
    final result = await _search.geocodeAddress(q);
    if (!mounted) return false;
    if (result == null) return false;
    final target = LatLng(result.latitude, result.longitude);
    _setDraftLocation(target, residentQuery: q);
    _settleAt(target, zoom: _addressZoom, reverse: true);
    return true;
  }

  Future<LocationPoint?> _resolveGps() async {
    final loc = context.read<LocationProvider>();
    try {
      if (loc.point == null) await loc.refresh();
    } catch (_) {
      return null;
    }
    return loc.point;
  }

  /// Moves the camera to [target] (no-op when the map is not attached yet —
  /// the initial centre then already matches). Optionally reverse-geocodes
  /// the target afterwards to back-fill a bare Step-2 address.
  void _settleAt(LatLng target, {required double zoom, bool reverse = false}) {
    try {
      _mapController.move(target, zoom);
    } catch (_) {
      // Map not attached yet — the initial centre already matches.
    }
    if (reverse) _requestReverseGeoCode(target);
  }

  /// Stores the coordinates into the draft (the final saved values) and
  /// remembers which Step-2 address they are resident for.
  void _setDraftLocation(LatLng point, {String? residentQuery}) {
    if (!mounted) return;
    widget.draft.latitude = point.latitude;
    widget.draft.longitude = point.longitude;
    _coordsQuery = residentQuery ?? _buildStep2Query();
    widget.onChanged();
  }

  /// The current Step-2 address query (raw, un-normalised — normalisation
  /// happens in the geocoding service).
  String _buildStep2Query() => widget.draft.addressQuery.trim();

  // ------------------------------------------------------------------
  // Map events (drag to re-pin)
  // ------------------------------------------------------------------
  void _onMapEvent(MapEvent event) {
    if (event is MapEventMoveEnd && !_seeding) {
      final c = event.camera.center;
      _setDraftLocation(c);
      _requestReverseGeoCode(c);
    }
  }

  /// Debounced reverse geocode: back-fills a bare Step-2 address after the
  /// map settles. Stale responses from older coordinates are dropped.
  void _requestReverseGeoCode(LatLng point) {
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(
      _reverseDebounceTime,
      () => _reverseGeoCode(point),
    );
  }

  Future<void> _reverseGeoCode(LatLng point) async {
    final seq = ++_reverseSeq;
    final resolved = await _search.reverseGeoCode(
      point.latitude,
      point.longitude,
    );
    if (!mounted || seq != _reverseSeq) return;
    // Only back-fill the draft address when the owner has not typed one.
    final address = resolved?.address;
    if (address != null &&
        address.trim().isNotEmpty &&
        widget.draft.address.trim().isEmpty) {
      widget.draft.address = address;
      // The coordinate is now resident for the filled address.
      _coordsQuery = _buildStep2Query();
      widget.onChanged();
    }
  }

  Future<void> _useMyLocation() async {
    final loc = context.read<LocationProvider>();
    // refresh() prompts for permission (if needed), detects disabled services
    // and returns the actual GPS coordinate — never a hard-coded fallback.
    await loc.refresh();
    if (!mounted) return;
    final point = loc.point;
    final access = loc.access;
    if (point == null) {
      final msg = switch (access) {
        LocationAccess.denied =>
          'Location permission denied. Allow location access in Settings to '
              'use your current position.',
        LocationAccess.disabled =>
          'Location services are turned off. Enable them to use your current '
              'position.',
        _ =>
          'Current location is not available yet. Try searching for the area '
              'instead.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    final target = LatLng(point.latitude, point.longitude);
    _setDraftLocation(target);
    _settleAt(target, zoom: 17, reverse: true);
  }

  // ------------------------------------------------------------------
  // Search (debounced suggestions + immediate keyboard-search geocode)
  // ------------------------------------------------------------------
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

  /// Keyboard "search" action: geocode the EXACT typed address and move the
  /// map + marker there (instead of only showing suggestions).
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
    _applySearchedResult(result);
  }

  void _applySearchedResult(PlaceSearchResult place) {
    _searchSeq++;
    _searchDebounce?.cancel();
    setState(() => _suggestions = []);
    final target = LatLng(place.latitude, place.longitude);
    _setDraftLocation(target);
    _settleAt(target, zoom: _addressZoom, reverse: true);
  }

  Future<void> _onSuggestionTap(PlaceSearchResult place) async {
    _searchSeq++; // invalidate any in-flight search
    _searchDebounce?.cancel();
    _searchController.text = place.name;
    _searchFocus.unfocus();
    _applySearchedResult(place);
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.draft.latitude;
    final lng = widget.draft.longitude;

    final searchField = Material(
      color: AppColors.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.search, color: AppColors.textSecondary),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _onSearchSubmitted(),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search area, street or landmark',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.textSecondary,
                onPressed: () {
                  _searchController.clear();
                  _searchSeq++;
                  setState(() => _suggestions = []);
                },
              ),
          ],
        ),
      ),
    );

    return Column(
      children: [
        Expanded(
          child: widget.active
              ? Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _initialCenter,
                        initialZoom: _defaultZoom,
                        onMapEvent: _onMapEvent,
                      ),
                      children: [
                        // Owner-side map only: aerial imagery so the owner can
                        // recognise the real plot, gate and driveway.
                        MapTiles.satellite(),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(
                                lat ?? _initialCenter.latitude,
                                lng ?? _initialCenter.longitude,
                              ),
                              width: 44,
                              height: 44,
                              alignment: Alignment.topCenter,
                              child: Container(
                                // Enables the E2E flow to wait until the
                                // coordinate has actually been seeded.
                                key: lat != null && lng != null
                                    ? const Key('owner-location-seeded')
                                    : null,
                                decoration: const BoxDecoration(
                                  color: AppColors.ownerPrimary,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'P',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        MapTiles.satelliteCredit(),
                      ],
                    ),
                    // Center crosshair hint
                    const IgnorePointer(
                      child: Center(
                        child: Icon(
                          Icons.location_on,
                          size: 48,
                          color: AppColors.ownerPrimary,
                        ),
                      ),
                    ),
                    // Search bar + suggestions overlay: full width on phones, capped on
                    // tablets/desktop.
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 12,
                      width: context.isTabletOrWider
                          ? ResponsiveLayout.mapOverlayMaxWidth
                          : null,
                      right: context.isTabletOrWider ? null : 12,
                      child: Column(
                        children: [
                          searchField,
                          if (_suggestions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Material(
                                color: AppColors.surface,
                                elevation: 2,
                                borderRadius: BorderRadius.circular(12),
                                clipBehavior: Clip.antiAlias,
                                // Bounded + internally scrollable so a long
                                // suggestion list cannot overflow the step.
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 320,
                                  ),
                                  child: ListView(
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    children: [
                                      for (final s in _suggestions)
                                        ListTile(
                                          dense: true,
                                          leading: const Icon(
                                            Icons.place_outlined,
                                            color: AppColors.ownerPrimary,
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                )
                                              : null,
                                          onTap: () => _onSuggestionTap(s),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                )
              : const Stack(children: [ColoredBox(color: AppColors.surface)]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Search an area, drag the map so the pin sits on the parking '
                  'space, or use your current position.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _useMyLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Use My Current Location'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ownerPrimary,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
