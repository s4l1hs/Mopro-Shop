import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/address/providers/address_form_controller.dart';
import 'package:mopro/features/address/providers/tr_provinces_provider.dart';

class AddressFormWidget extends ConsumerWidget {
  const AddressFormWidget({required this.editId, super.key});

  final int? editId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formState = ref.watch(addressFormProvider(editId));
    final provincesAsync = ref.watch(trProvincesProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TextField(
          label: 'address.label'.tr(),
          value: formState.label,
          onChanged: ref.read(addressFormProvider(editId).notifier).setLabel,
        ),
        const SizedBox(height: 12),
        _TextField(
          label: 'address.name'.tr(),
          value: formState.name,
          onChanged: ref.read(addressFormProvider(editId).notifier).setName,
        ),
        const SizedBox(height: 12),
        _TextField(
          label: 'address.phone'.tr(),
          value: formState.phone,
          onChanged: ref.read(addressFormProvider(editId).notifier).setPhone,
          keyboardType: TextInputType.phone,
          hint: '+905XXXXXXXXX',
        ),
        const SizedBox(height: 12),
        provincesAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (_, __) => Text('common.error'.tr()),
          data: (provinces) => _ProvinceDropdowns(
            provinces: provinces,
            selectedCity: formState.city,
            selectedDistrict: formState.district,
            onCityChanged:
                ref.read(addressFormProvider(editId).notifier).setCity,
            onDistrictChanged:
                ref.read(addressFormProvider(editId).notifier).setDistrict,
          ),
        ),
        const SizedBox(height: 12),
        _TextField(
          label: 'address.neighborhood'.tr(),
          value: formState.neighborhood,
          onChanged:
              ref.read(addressFormProvider(editId).notifier).setNeighborhood,
          required: false,
        ),
        const SizedBox(height: 12),
        _TextField(
          label: 'address.full_address'.tr(),
          value: formState.fullAddress,
          onChanged:
              ref.read(addressFormProvider(editId).notifier).setFullAddress,
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        _TextField(
          label: 'address.postal_code'.tr(),
          value: formState.postalCode,
          onChanged:
              ref.read(addressFormProvider(editId).notifier).setPostalCode,
          keyboardType: TextInputType.number,
          required: false,
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          title: Text('address.set_as_default'.tr()),
          value: formState.isDefault,
          onChanged: (v) => ref
              .read(addressFormProvider(editId).notifier)
              .setIsDefault(v ?? false),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class _TextField extends StatefulWidget {
  const _TextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.required = true,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool required;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.required
            ? '${widget.label} *'
            : widget.label,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
      ),
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
    );
  }
}

class _ProvinceDropdowns extends StatelessWidget {
  const _ProvinceDropdowns({
    required this.provinces,
    required this.selectedCity,
    required this.selectedDistrict,
    required this.onCityChanged,
    required this.onDistrictChanged,
  });

  final List<Province> provinces;
  final String selectedCity;
  final String selectedDistrict;
  final ValueChanged<String> onCityChanged;
  final ValueChanged<String> onDistrictChanged;

  @override
  Widget build(BuildContext context) {
    final districts = provinces
        .where((p) => p.name == selectedCity)
        .firstOrNull
        ?.districts ?? [];

    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: selectedCity.isEmpty ? null : selectedCity,
          decoration: InputDecoration(
            labelText: 'address.city'.tr() + ' *',
            border: const OutlineInputBorder(),
          ),
          items: provinces
              .map((p) => DropdownMenuItem(value: p.name, child: Text(p.name)))
              .toList(),
          onChanged: (v) {
            if (v != null) onCityChanged(v);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: selectedDistrict.isEmpty ? null : selectedDistrict,
          decoration: InputDecoration(
            labelText: 'address.district'.tr() + ' *',
            border: const OutlineInputBorder(),
          ),
          items: districts
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: (v) {
            if (v != null) onDistrictChanged(v);
          },
        ),
      ],
    );
  }
}
