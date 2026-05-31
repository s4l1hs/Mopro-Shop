import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/notifications/application/notification_preferences_provider.dart';
import 'package:mopro/features/notifications/data/notification_dto.dart';

/// Category × channel toggle grid. Transactional in-app channels are forced on
/// (toggling off shows a SnackBar and stays on).
class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  static const _categories = [
    NotificationType.orderStatus,
    NotificationType.returnUpdate,
    NotificationType.security,
    NotificationType.marketing,
    'general',
  ];
  static const _channels = [
    NotificationChannel.inApp,
    NotificationChannel.email,
    NotificationChannel.push,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationPreferencesProvider);
    final notifier = ref.read(notificationPreferencesProvider.notifier);

    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('notifications.prefs_title'.tr())),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final cat in _categories)
                  _CategoryBlock(
                    category: cat,
                    channels: _channels,
                    state: state,
                    onToggle: ({required channel, required value}) {
                      final ok = notifier.toggle(
                        category: cat,
                        channel: channel,
                        enabled: value,
                      );
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('notifications.forced_on_warning'.tr())),
                        );
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.category,
    required this.channels,
    required this.state,
    required this.onToggle,
  });

  final String category;
  final List<String> channels;
  final PreferencesState state;
  final void Function({required String channel, required bool value}) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(
            'notifications.cat_$category'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        for (final ch in channels)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('notifications.ch_$ch'.tr()),
            value: state.isEnabled(category, ch),
            onChanged: (v) => onToggle(channel: ch, value: v),
          ),
        const Divider(),
      ],
    );
  }
}
