import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/data/vehicle_data.dart';
import '../../core/network/error_messages.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/validators.dart';
import '../../modules/auth/providers/auth_provider.dart';
import '../../modules/user/providers/user_home_tab_provider.dart';
import '../../modules/user/providers/user_map_provider.dart';
import '../../modules/vehicle/providers/vehicle_provider.dart';
import '../../shared/models/vehicle.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/meter_field.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/responsive/responsive_layout.dart';

/// Add / edit a saved vehicle — updated with Image 6 UI layout & styling.
class VehicleFormScreen extends StatefulWidget {
  final Vehicle? vehicle;
  const VehicleFormScreen({super.key, this.vehicle});

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  late String _type;
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _reg;
  double? _lengthM;
  double? _widthM;
  double? _heightM;
  bool _saving = false;
  bool _showOtherModel = false;
  late final TextEditingController _otherModel;

  bool get _isEdit => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _type = v?.vehicleType ?? VehicleType.car;
    _brand = TextEditingController(text: v?.brand ?? '');
    _model = TextEditingController(text: v?.model ?? '');
    _reg = TextEditingController(text: v?.registrationNumber ?? '');
    _lengthM = v?.lengthM;
    _widthM = v?.widthM;
    _heightM = v?.heightM;
    _otherModel = TextEditingController();
    // Check if it's an 'Others' model
    final models = VehicleData.getModelsForType(_getDisplayType());
    final modelValue = v?.model;
    if (modelValue != null &&
        modelValue.isNotEmpty &&
        !models.contains(modelValue)) {
      _showOtherModel = true;
      _otherModel.text = modelValue;
    }
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _reg.dispose();
    _otherModel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    final provider = context.read<VehicleProvider>();
    final token = auth.accessToken ?? '';

    final valid = _validate();
    if (valid != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(valid)));
      return;
    }

    final payload = <String, dynamic>{
      'vehicleType': _type,
      'brand': _brand.text.trim(),
      'model': _showOtherModel ? _otherModel.text.trim() : _model.text.trim(),
      'registrationNumber': _reg.text.trim().toUpperCase(),
      'lengthM': _lengthM ?? (_type == VehicleType.car ? 4.2 : 2.0),
      'widthM': _widthM ?? (_type == VehicleType.car ? 1.8 : 0.8),
      'heightM': _heightM ?? (_type == VehicleType.car ? 1.5 : 1.1),
    };

    setState(() => _saving = true);
    try {
      late final Vehicle saved;
      if (_isEdit) {
        saved = await provider.update(
          id: widget.vehicle!.id,
          token: token,
          payload: payload,
        );
      } else {
        if (provider.vehicles.isEmpty) payload['isPrimary'] = true;
        saved = await provider.create(token: token, payload: payload);
      }
      if (!mounted) return;
      context.read<UserMapProvider>().setActiveVehicle(
        saved.id,
        saved.vehicleType,
      );
      context.read<UserHomeTabProvider>().show(UserTab.map);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ErrorMessages.logTechnical('vehicle.save', e);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ErrorMessages.unableToUpdateVehicle)),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _getDisplayType() {
    if (_type == VehicleType.bike) return 'Bike';
    if (_type == 'scooty' || _type == 'Scooty') return 'Scooty';
    return 'Car';
  }

  String? _validate() {
    if (_brand.text.trim().isEmpty) return 'Enter the brand name';
    final modelText = _showOtherModel ? _otherModel.text : _model.text;
    if (modelText.trim().isEmpty) return 'Enter the vehicle Model';
    final regError = Validators.registration(_reg.text);
    if (regError != null) return regError;
    return null;
  }

  Widget _buildStepIndicator(int currentStep) {
    final steps = [
      'Personal Details',
      'Vehicle Details',
      'Preferences',
      'Photos',
    ];
    const accent = AppColors.brandBlue;
    return Row(
      children: List.generate(steps.length, (i) {
        final stepNum = i + 1;
        final isActive = stepNum == currentStep;
        final isDone = stepNum < currentStep;
        final color = (isActive || isDone) ? accent : Colors.grey.shade300;
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i == 0
                          ? Colors.transparent
                          : (isDone ? accent : Colors.grey.shade300),
                    ),
                  ),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isActive || isDone) ? accent : Colors.white,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '$stepNum',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: (isActive || isDone)
                              ? Colors.white
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: i == steps.length - 1
                          ? Colors.transparent
                          : (isDone ? accent : Colors.grey.shade300),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                steps[i],
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? accent : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ConstrainedContent(
        maxWidth: ResponsiveLayout.formMaxWidth,
        child: ListView(
          // ignore: deprecated_member_use
          cacheExtent: 1200,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          children: [
            Center(
              child: Image.asset(
                'assets/images/parkshare/logo.png',
                height: 38,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Vehicle information',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tell us about your vehicle',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            _buildStepIndicator(2),
            const SizedBox(height: 24),

            CustomTextField(
              label: 'Vechicle Number',
              hint: 'Enter your vehicle number',
              controller: _reg,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              onChanged: (v) {
                final upper = v.toUpperCase();
                if (upper != v) {
                  _reg.value = TextEditingValue(
                    text: upper,
                    selection: TextSelection.collapsed(offset: upper.length),
                  );
                }
              },
            ),
            const SizedBox(height: 18),

            const Text(
              'Vehicle Type',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildTypePill('Car', VehicleType.car),
                const SizedBox(width: 12),
                _buildTypePill('Bike', VehicleType.bike),
                const SizedBox(width: 12),
                _buildTypePill('Scooty', 'scooty'),
              ],
            ),
            const SizedBox(height: 18),

            CustomTextField(
              label: 'Brand',
              hint: 'Enter your vehicle brand name',
              controller: _brand,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 18),

            _ModelField(
              vehicleType: _getDisplayType(),
              initialValue: _model.text,
              onSelected: (value) {
                setState(() {
                  _model.text = value;
                  _showOtherModel = value == 'Others';
                  if (_showOtherModel) {
                    _otherModel.text = '';
                  }
                });
              },
              onChanged: (value) {
                setState(() {
                  _model.text = value;
                  _showOtherModel = value == 'Others';
                  if (_showOtherModel && value != 'Others') {
                    _showOtherModel = false;
                  }
                });
              },
            ),
            if (_showOtherModel) ...[
              const SizedBox(height: 18),
              CustomTextField(
                label: 'Enter Model Name',
                hint: 'Specify your vehicle model',
                controller: _otherModel,
                textInputAction: TextInputAction.next,
              ),
            ],
            const SizedBox(height: 24),

            Text(
              'Dimensions (feet)',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Used for parking fit check',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: MeterField(
                    label: 'Length',
                    unit: 'ft',
                    hint: '13.78',
                    initialValue: _lengthM == null
                        ? null
                        : Helpers.metersToFeet(_lengthM!),
                    onChanged: (v) => setState(
                      () =>
                          _lengthM = v == null ? null : Helpers.feetToMeters(v),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MeterField(
                    label: 'Width',
                    unit: 'ft',
                    hint: '5.91',
                    initialValue: _widthM == null
                        ? null
                        : Helpers.metersToFeet(_widthM!),
                    onChanged: (v) => setState(
                      () =>
                          _widthM = v == null ? null : Helpers.feetToMeters(v),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MeterField(
                    label: 'Height',
                    unit: 'ft',
                    hint: '4.92',
                    initialValue: _heightM == null
                        ? null
                        : Helpers.metersToFeet(_heightM!),
                    onChanged: (v) => setState(
                      () =>
                          _heightM = v == null ? null : Helpers.feetToMeters(v),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: PrimaryButton(
            label: 'Save & Find Parking',
            loading: _saving,
            onPressed: _saving ? null : _save,
            backgroundColor: AppColors.brandBlue,
          ),
        ),
      ),
    );
  }

  Widget _buildTypePill(String label, String value) {
    final selected =
        _type == value || (_type == VehicleType.bike && value == 'scooty');
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = value == 'scooty' ? VehicleType.bike : value;
          // Reset model when type changes
          _model.clear();
          _otherModel.clear();
          _showOtherModel = false;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.brandBlue : Colors.grey.shade300,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? AppColors.brandBlue : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration get _modelDecoration => InputDecoration(
  hintStyle: const TextStyle(color: AppColors.textHint),
  suffixIcon: const Icon(
    Icons.arrow_drop_down,
    color: AppColors.textSecondary,
    size: 24,
  ),
  filled: true,
  fillColor: AppColors.surface,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.6),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.error),
  ),
  focusedErrorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.error, width: 1.6),
  ),
);

class _ModelField extends StatelessWidget {
  final String vehicleType;
  final String initialValue;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onChanged;

  const _ModelField({
    required this.vehicleType,
    required this.initialValue,
    required this.onSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final models = VehicleData.getModelsForType(vehicleType);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Model',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        RawAutocomplete<String>(
          key: ValueKey('model_$vehicleType'),
          initialValue: TextEditingValue(text: initialValue),
          optionsBuilder: (textEditingValue) =>
              VehicleData.match(textEditingValue.text, models),
          onSelected: onSelected,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.next,
              onChanged: onChanged,
              onSubmitted: (_) => onFieldSubmitted(),
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
              decoration: _modelDecoration.copyWith(hintText: 'Select model'),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList(growable: false);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final option = list[index];
                      final highlighted =
                          AutocompleteHighlightedOption.of(context) == index;
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Container(
                          width: double.infinity,
                          color: highlighted
                              ? AppColors.userPrimaryLight
                              : Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Text(
                            option,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
