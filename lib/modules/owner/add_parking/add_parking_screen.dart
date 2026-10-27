import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/services/photo_picker_service.dart';
import '../../../modules/auth/providers/auth_provider.dart';
import '../../../shared/models/parking.dart';
import '../../../shared/models/parking_space.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/responsive/responsive_layout.dart';
import '../../owner/providers/owner_parking_provider.dart';
import 'parking_draft.dart';
import 'steps/about_step.dart';
import 'steps/amenities_step.dart';
import 'steps/capacity_step.dart';
import 'steps/details_step.dart';
import 'steps/dimensions_step.dart';
import 'steps/location_step.dart';
import 'steps/photo_step.dart';
import 'steps/rental_step.dart';
import 'steps/review_step.dart';
import 'steps/spaces_step.dart';

/// The wizard steps, in order. Amenities stays right after the capacity/space
/// steps; only the parking-dimension block was extended.
enum _Step {
  photos('Photos'),
  details('Details'),
  location('Location'),
  dimensions('Dimensions'),
  capacity('Capacity'),
  spaces('Spaces'),
  amenities('Amenities'),
  rental('Rental'),
  about('About'),
  review('Review');

  const _Step(this.label);
  final String label;
}

/// Owner parking wizard — 10 steps:
/// Photos -> Details -> Location -> Dimensions -> Capacity -> Spaces ->
/// Amenities -> Rental -> About -> Review (real draft preview) -> Publish.
///
/// The same screen also serves Edit Parking: pass [existing] and the draft is
/// prefilled from the saved listing and the final button reads "Update Parking".
/// There is deliberately no duplicate edit screen.
class AddParkingScreen extends StatefulWidget {
  final ParkingListing? existing;

  const AddParkingScreen({super.key, this.existing});

  bool get isEditing => existing != null;

  @override
  State<AddParkingScreen> createState() => _AddParkingScreenState();
}

class _AddParkingScreenState extends State<AddParkingScreen> {
  late final ParkingDraft _draft = _buildDraft();
  final PhotoPickerService _picker = PhotoPickerFactory.create();

  int _step = 0;
  bool _saving = false;

  /// Builds the draft from [existing] when editing, otherwise from defaults.
  /// Pre-existing photo URLs are kept alongside any newly picked photos.
  ParkingDraft _buildDraft() {
    final d = ParkingDraft();
    final p = widget.existing;
    if (p == null) {
      d.state = 'Tamil Nadu';
      d.city = 'Chennai';
      return d;
    }
    d.parkingName = p.parkingName;
    d.address = p.address;
    d.city = p.city ?? '';
    d.state = p.state ?? '';
    d.pincode = p.pincode ?? '';
    d.landmark = p.landmark ?? '';
    d.latitude = p.latitude;
    d.longitude = p.longitude;
    d.lengthM = p.lengthM;
    d.widthM = p.widthM;
    d.heightM = p.heightM;
    d.entranceLengthM = p.entranceLengthM;
    d.entranceWidthM = p.entranceWidthM;
    d.entranceHeightM = p.entranceHeightM;
    d.parkingType = p.parkingType;
    d.carMonthlyEnabled = p.carMonthlyEnabled;
    d.carMonthlyRent = p.carMonthlyRent;
    d.carYearlyEnabled = p.carYearlyEnabled;
    d.carYearlyRent = p.carYearlyRent;
    d.bikeMonthlyEnabled = p.bikeMonthlyEnabled;
    d.bikeMonthlyRent = p.bikeMonthlyRent;
    d.bikeYearlyEnabled = p.bikeYearlyEnabled;
    d.bikeYearlyRent = p.bikeYearlyRent;
    d.accessHours = p.accessHours;
    d.description = p.description;
    d.conditions = p.conditions;
    d.autoApproval = p.autoApproval;
    // Amenities the form no longer offers (removed options) are dropped so
    // they cannot silently ride along in the payload.
    d.amenities.addAll(p.amenities.where(ParkingAmenity.all.contains));
    d.allowMixedParking = p.allowMixedParking;
    // Capacity comes from the real slot rows, never from the stored counters.
    d.maximumCars = p.totalCarSpaces;
    d.maximumBikes = p.totalBikeSpaces;
    d.spaces.addAll(p.spaces);
    // A listing saved before slot allocation: seed one EMPTY row per vehicle
    // type so the owner is not asked to re-enter capacity they already gave.
    // The measurements stay blank on purpose — the plot size is never used as a
    // slot default, so the owner types the real bay size.
    if (d.spaces.isEmpty) {
      if (p.acceptsCars) {
        d.spaces.add(ParkingSpace.draft(spaceCode: 'C1', vehicleType: 'CAR'));
      }
      if (p.acceptsBikes) {
        d.spaces.add(ParkingSpace.draft(spaceCode: 'B1', vehicleType: 'BIKE'));
      }
    }
    return d;
  }

  void _onChanged() => setState(() {});

  /// Per-step validation. Every step is guarded, so the owner can never reach
  /// Review with an incomplete listing.
  String? _stepError(int step) {
    switch (_step) {
      case 0:
        return _draft.photos.isEmpty && _photoUrls.isEmpty
            ? 'Add at least one photo.'
            : null;
      case 1:
        if (_draft.parkingName.trim().isEmpty ||
            _draft.address.trim().isEmpty) {
          return 'Enter the parking name and address.';
        }
        return null;
      case 2:
        return (_draft.latitude == null || _draft.longitude == null)
            ? 'Drag the map to pin the parking location.'
            : null;
      case 3:
        if (_draft.lengthM == null ||
            _draft.widthM == null ||
            _draft.heightM == null) {
          return 'Parking length, width and height are required.';
        }
        if (_draft.lengthM! <= 0 ||
            _draft.widthM! <= 0 ||
            _draft.heightM! <= 0) {
          return 'All parking dimensions must be greater than 0.';
        }
        if ((_draft.entranceWidthM ?? 0) <= 0) {
          return 'Enter the gate width — it decides what can get in.';
        }
        if ((_draft.entranceHeightM ?? 0) <= 0) {
          return 'Enter the gate height — it decides what can get in.';
        }
        // Optional field, but if it was filled in it must be positive.
        if (_draft.entranceLengthM != null && _draft.entranceLengthM! <= 0) {
          return 'Gate length must be greater than 0.';
        }
        return null;
      case 4:
        if (_draft.maximumCars == 0 && _draft.maximumBikes == 0) {
          return 'Set at least one car space or one bike space.';
        }
        return null;
      case 5:
        return _draft.spacesError;
      case 7:
        if (!_draft.anyRentalPlanEnabled) {
          return 'Enable at least one rental plan (car and/or bike).';
        }
        return _draft.rentalPlansError;
      default:
        return null;
    }
  }

  /// Photos already stored on the listing being edited (no re-upload needed).
  List<String> get _photoUrls => widget.existing?.photoUrls ?? const [];

  bool get _isLast => _step == _Step.values.length - 1;

  Future<void> _next() async {
    if (!_isLast) {
      final err = _stepError(_step);
      if (err != null) {
        _toast(err);
        return;
      }
      setState(() => _step++);
      return;
    }
    await _save();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final validation = _draft.validateForPublish();
    if (validation != null) {
      _toast(validation);
      return;
    }
    final auth = context.read<AuthProvider>();
    final provider = context.read<OwnerParkingProvider>();
    final token = auth.accessToken;
    if (token == null || token.isEmpty) return;

    setState(() => _saving = true);
    try {
      // New photos are uploaded first; the already-stored URLs are reused.
      final uploaded = _draft.photos.isEmpty
          ? const <String>[]
          : await provider.uploadPhotos(token: token, photos: _draft.photos);
      final urls = <String>[..._photoUrls, ...uploaded];

      final payload = _draft.toPayload(urls);
      final existing = widget.existing;
      final saved = existing == null
          ? await provider.publish(token: token, payload: payload)
          : await provider.update(
              token: token,
              parkingId: existing.id,
              payload: payload,
            );
      if (!mounted) return;
      _toast(
        widget.isEditing
            ? '"${saved.parkingName}" updated.'
            : '"${saved.parkingName}" published!',
      );
      Navigator.of(context).pop(saved);
    } catch (e) {
      ErrorMessages.logTechnical('parking.save', e);
      if (!mounted) return;
      _toast(
        ErrorMessages.forUi(
          e,
          fallback: widget.isEditing
              ? ErrorMessages.saveParkingFailed
              : ErrorMessages.saveParkingFailed,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _goToStep(int index) {
    // Only allow jumping backwards, and only past steps that are already valid.
    if (index >= _step) return;
    setState(() => _step = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.isEditing ? 'Edit' : 'Add'} Parking '
          '(${_step + 1}/${_Step.values.length})',
        ),
        actions: [
          if (_step > 0)
            TextButton(
              onPressed: _saving ? null : () => setState(() => _step--),
              child: const Text('Back'),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: _StepBar(
            steps: _Step.values,
            current: _step,
            onTap: _goToStep,
          ),
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            // Derived from the step list, never a hardcoded /8.
            value: (_step + 1) / _Step.values.length,
            backgroundColor: AppColors.border,
            color: AppColors.ownerPrimary,
            minHeight: 4,
          ),
          Expanded(
            // Steps cap their width on tablets/desktop so forms and lists
            // stay readable; phones are unaffected.
            child: ConstrainedContent(
              maxWidth: ResponsiveLayout.readingMaxWidth,
              child: IndexedStack(index: _step, children: _buildSteps()),
            ),
          ),
          SafeArea(
            child: ConstrainedContent(
              maxWidth: ResponsiveLayout.formMaxWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PrimaryButton(
                  label: _isLast
                      ? (widget.isEditing
                            ? 'Update Parking'
                            : 'Publish Parking')
                      : 'Next',
                  loading: _saving,
                  onPressed: _saving ? null : _next,
                  icon: _isLast ? Icons.check_circle_outline : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSteps() => [
    PhotoStep(draft: _draft, picker: _picker, onChanged: _onChanged),
    DetailsStep(draft: _draft, onChanged: _onChanged),
    LocationStep(draft: _draft, onChanged: _onChanged, active: _step == 2),
    DimensionsStep(draft: _draft, onChanged: _onChanged),
    CapacityStep(draft: _draft, onChanged: _onChanged),
    SpacesStep(draft: _draft, onChanged: _onChanged),
    AmenitiesStep(draft: _draft, onChanged: _onChanged),
    RentalStep(draft: _draft, onChanged: _onChanged),
    AboutStep(draft: _draft, onChanged: _onChanged),
    ReviewStep(draft: _draft, isEditing: widget.isEditing),
  ];
}

/// Compact dot/label progress strip so the owner can see how long the wizard is
/// and jump back to a step already completed.
class _StepBar extends StatelessWidget {
  final List<_Step> steps;
  final int current;
  final ValueChanged<int> onTap;

  const _StepBar({
    required this.steps,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: steps.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final done = i < current;
          final active = i == current;
          final enabled = i < current;
          return GestureDetector(
            onTap: enabled ? () => onTap(i) : null,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.ownerPrimary
                    : done
                    ? AppColors.ownerPrimaryLight
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (done)
                    const Icon(
                      Icons.check,
                      size: 13,
                      color: AppColors.ownerPrimary,
                    )
                  else
                    Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(width: 5),
                  Text(
                    steps[i].label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Colors.white
                          : done
                          ? AppColors.ownerPrimaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
