import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccountProfileScreen extends ConsumerStatefulWidget {
  const AccountProfileScreen({super.key});

  @override
  ConsumerState<AccountProfileScreen> createState() =>
      _AccountProfileScreenState();
}

class _AccountProfileScreenState extends ConsumerState<AccountProfileScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _tcIdCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _tcIdCtrl.dispose();
    super.dispose();
  }

  String? _validateTcId(String? v) {
    if (v == null || v.isEmpty) return null; // optional
    if (v.length != 11) return 'profile.tc_id_length'.tr();
    if (v[0] == '0') return 'profile.tc_id_no_zero'.tr();
    if (!RegExp(r'^\d{11}$').hasMatch(v)) return 'profile.tc_id_digits'.tr();
    final digits = v.split('').map(int.parse).toList();
    final odd = digits[0] + digits[2] + digits[4] + digits[6] + digits[8];
    final even = digits[1] + digits[3] + digits[5] + digits[7];
    if ((odd * 7 - even) % 10 != digits[9]) return 'profile.tc_id_invalid'.tr();
    final sum10 = digits.take(10).fold(0, (a, b) => a + b);
    if (sum10 % 10 != digits[10]) return 'profile.tc_id_invalid'.tr();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('account.profile'.tr())),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _firstNameCtrl,
              decoration: InputDecoration(
                labelText: 'auth.name_first'.tr(),
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'profile.required'.tr()
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _lastNameCtrl,
              decoration: InputDecoration(
                labelText: 'auth.name_last'.tr(),
                border: const OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'profile.required'.tr()
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _tcIdCtrl,
              keyboardType: TextInputType.number,
              maxLength: 11,
              decoration: InputDecoration(
                labelText: 'profile.tc_id'.tr(),
                helperText: 'profile.tc_id_helper'.tr(),
                border: const OutlineInputBorder(),
              ),
              validator: _validateTcId,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () {
                if (_formKey.currentState?.validate() ?? false) {
                  // TODO(mopro): wire to profile update API
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('profile.saved'.tr())),
                  );
                }
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text('profile.save'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
