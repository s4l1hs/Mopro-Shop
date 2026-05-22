import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/auth/auth_profile_notifier.dart';

const _supportedLocales = [
  ('tr-TR', 'Türkçe'),
  ('en-US', 'English'),
  ('de-DE', 'Deutsch'),
  ('ar-AE', 'العربية'),
];

class ProfileCompletionScreen extends ConsumerWidget {
  const ProfileCompletionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authProfileNotifierProvider);
    final notifier = ref.read(authProfileNotifierProvider.notifier);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                Text(
                  'auth.profile_title'.tr(),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'auth.profile_subtitle'.tr(),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'auth.name_first'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onChanged: notifier.onNameFirstChanged,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'auth.name_last'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onChanged: notifier.onNameLastChanged,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: state.locale,
                  decoration: InputDecoration(
                    labelText: 'auth.locale'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _supportedLocales
                      .map(
                        (l) => DropdownMenuItem(
                          value: l.$1,
                          child: Text(l.$2),
                        ),
                      )
                      .toList(),
                  onChanged: notifier.onLocaleChanged,
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'auth.unknown_error'.tr(),
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: state.canSubmit ? notifier.submit : null,
                    child: state.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : Text('auth.complete_profile'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
