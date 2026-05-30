import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';

/// Minimal placeholder for account rail destinations whose real screens are not
/// implemented yet (Notifications, Help). Renders inside the account two-pane on
/// desktop (rail highlighted) and full-screen on mobile. Surfaced as Backlog.
class AccountPlaceholderScreen extends StatelessWidget {
  const AccountPlaceholderScreen({
    required this.titleKey,
    required this.icon,
    super.key,
  });

  final String titleKey;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text(titleKey.tr())),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(
              titleKey.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'account.coming_soon'.tr(),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
