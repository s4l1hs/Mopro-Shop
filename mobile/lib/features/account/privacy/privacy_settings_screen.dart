import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';
import 'package:mopro/features/home/recently_viewed_provider.dart';

/// `/account/privacy` — analytics consent toggle + RTBF erase + policy link
/// (Tranche 4b, Decisions 3 & 5). Unlike the banner this screen is always
/// available to authed users (the persistent privacy control).
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('consent.delete_confirm_title'.tr()),
        content: Text('consent.delete_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    final ok = await ref.read(userConsentProvider.notifier).deleteAllData();
    if (ok) {
      // Visibly empty the "Son baktıkların" rail after erase (Tranche 4c).
      ref.invalidate(recentlyViewedProvider);
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'consent.deleted_toast'.tr() : 'consent.delete_error'.tr(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final consent = ref.watch(userConsentProvider);

    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('consent.settings_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Analitik İzleme ───────────────────────────────────────────────
          Text(
            'consent.setting_title'.tr(),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            value: consent.analyticsEnabled,
            onChanged: consent.loading
                ? null
                : (v) => ref.read(userConsentProvider.notifier).setConsent(v),
            activeThumbColor: cs.primary,
            contentPadding: EdgeInsets.zero,
            title: Text('consent.setting_desc'.tr()),
            subtitle: Text(
              consent.analyticsEnabled
                  ? 'consent.setting_on_help'.tr()
                  : 'consent.setting_off_help'.tr(),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const Divider(height: 32),

          // ── Verilerini Yönet (RTBF) ───────────────────────────────────────
          Text(
            'consent.manage_section'.tr(),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirmDelete(context, ref),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text('consent.delete_all'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const Divider(height: 32),

          // ── Daha Fazla Bilgi ──────────────────────────────────────────────
          Text(
            'consent.more_section'.tr(),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.shield_outlined, color: cs.primary),
            title: Text('consent.read_policy'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/help/article/privacy-and-tracking'),
          ),
        ],
      ),
    );
  }
}
