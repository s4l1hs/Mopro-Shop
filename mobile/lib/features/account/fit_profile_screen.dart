import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/features/account/providers/fit_profile_provider.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro_api/mopro_api.dart';

/// Size-fit phase 1: the fit-profile form ("Beden Profilim"). Measurements are
/// entered in CM and sent as integer MM; they are stored AES-GCM-encrypted
/// server-side. Saving upserts (PUT, idempotent).
class FitProfileScreen extends ConsumerStatefulWidget {
  const FitProfileScreen({super.key});

  @override
  ConsumerState<FitProfileScreen> createState() => _FitProfileScreenState();
}

class _FitProfileScreenState extends ConsumerState<FitProfileScreen> {
  final _controllers = <String, TextEditingController>{
    'chest': TextEditingController(),
    'waist': TextEditingController(),
    'hip': TextEditingController(),
    'inseam': TextEditingController(),
    'height': TextEditingController(),
    'weight': TextEditingController(),
  };
  String _fitPref = 'regular';
  String _gender = 'unspecified';
  bool _hydrated = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(FitProfileEnvelope env) {
    if (_hydrated) return;
    _hydrated = true;
    final p = env.profile;
    if (p == null) return;
    void set(String key, int? mm) {
      if (mm != null) _controllers[key]!.text = '${mm ~/ 10}';
    }

    set('chest', p.chestMm);
    set('waist', p.waistMm);
    set('hip', p.hipMm);
    set('inseam', p.inseamMm);
    set('height', p.heightMm);
    if (p.weightG != null) _controllers['weight']!.text = '${p.weightG! ~/ 1000}';
    _gender = p.gender ?? 'unspecified';
    _fitPref = p.fitPref;
  }

  int? _mm(String key) {
    final t = _controllers[key]!.text.trim();
    if (t.isEmpty) return null;
    final cm = int.tryParse(t);
    return cm == null ? null : cm * 10;
  }

  int? _grams(String key) {
    final t = _controllers[key]!.text.trim();
    if (t.isEmpty) return null;
    final kg = int.tryParse(t);
    return kg == null ? null : kg * 1000;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(meApiProvider).putMyFitProfile(
            fitProfile: FitProfile(
              chestMm: _mm('chest'),
              waistMm: _mm('waist'),
              hipMm: _mm('hip'),
              inseamMm: _mm('inseam'),
              heightMm: _mm('height'),
              weightG: _grams('weight'),
              gender: _gender,
              fitPref: _fitPref,
            ),
          );
      ref.invalidate(fitProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('fit.saved'.tr())),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('fit.save_failed'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(fitProfileProvider);
    final env = state.valueOrNull;
    if (env != null) _hydrate(env);

    Widget field(String key, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _controllers[key],
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: label,
              suffixText: 'fit.cm'.tr(),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );

    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('fit.title'.tr())),
      body: state.isLoading && env == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('fit.intro'.tr(), style: theme.textTheme.bodyMedium),
                const SizedBox(height: 6),
                Text(
                  'fit.privacy_note'.tr(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                field('chest', 'fit.chest'.tr()),
                field('waist', 'fit.waist'.tr()),
                field('hip', 'fit.hip'.tr()),
                field('inseam', 'fit.inseam'.tr()),
                field('height', 'fit.height'.tr()),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _controllers['weight'],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'fit.weight'.tr(),
                      suffixText: 'fit.kg'.tr(),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                Text('fit.gender_label'.tr(), style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'female',
                      label: Text('fit.gender_female'.tr()),
                    ),
                    ButtonSegment(
                      value: 'male',
                      label: Text('fit.gender_male'.tr()),
                    ),
                    ButtonSegment(
                      value: 'unspecified',
                      label: Text('fit.gender_unspecified'.tr()),
                    ),
                  ],
                  selected: {_gender},
                  onSelectionChanged: (sel) =>
                      setState(() => _gender = sel.first),
                ),
                const SizedBox(height: 8),
                Text(
                  'fit.basic_hint'.tr(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Text('fit.pref_label'.tr(), style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'tight',
                      label: Text('fit.pref_tight'.tr()),
                    ),
                    ButtonSegment(
                      value: 'regular',
                      label: Text('fit.pref_regular'.tr()),
                    ),
                    ButtonSegment(
                      value: 'loose',
                      label: Text('fit.pref_loose'.tr()),
                    ),
                  ],
                  selected: {_fitPref},
                  onSelectionChanged: (s) =>
                      setState(() => _fitPref = s.first),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('fit.save'.tr()),
                ),
              ],
            ),
    );
  }
}
