import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/address/providers/address_form_controller.dart';
import 'package:mopro/features/address/providers/addresses_provider.dart';
import 'package:mopro/features/address/widgets/address_form.dart';
import 'package:mopro_api/mopro_api.dart';

class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({this.editAddress, super.key});

  final Address? editAddress;

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  @override
  void initState() {
    super.initState();
    final address = widget.editAddress;
    if (address != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(addressFormProvider(address.id).notifier)
            .prefill(address);
      });
    }
  }

  int? get _editId => widget.editAddress?.id;

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(addressFormProvider(_editId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editId != null
              ? 'address.edit_title'.tr()
              : 'address.new_title'.tr(),
        ),
      ),
      body: Column(
        children: [
          if (formState.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ErrorBanner(
                error: formState.error!,
              ),
            ),
          Expanded(child: AddressFormWidget(editId: _editId)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: formState.submitting || !formState.isValid
                ? null
                : () => _submit(context),
            child: formState.submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('address.save'.tr()),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final result = await ref
        .read(addressFormProvider(_editId).notifier)
        .submit();
    if (result != null && context.mounted) {
      ref.invalidate(addressesProvider);
      context.pop();
    }
  }
}
