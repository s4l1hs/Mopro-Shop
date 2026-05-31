import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/notifications/application/notifications_provider.dart';
import 'package:mopro/features/notifications/data/notification_dto.dart';
import 'package:mopro/features/notifications/widgets/notification_row.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  NotificationFilter _filter = NotificationFilter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(notificationsProvider(_filter));
    final notifier = ref.read(notificationsProvider(_filter).notifier);
    final hasUnread = state.items.any((n) => !n.isRead);

    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('notifications.title'.tr())),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'notifications.title'.tr(),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                _FilterChip(
                  label: 'notifications.filter_all'.tr(),
                  selected: _filter == NotificationFilter.all,
                  onTap: () => setState(() => _filter = NotificationFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'notifications.filter_unread'.tr(),
                  selected: _filter == NotificationFilter.unread,
                  onTap: () =>
                      setState(() => _filter = NotificationFilter.unread),
                ),
              ],
            ),
          ),
          if (hasUnread)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextButton(
                  onPressed: notifier.markAllRead,
                  child: Text('notifications.mark_all_read'.tr()),
                ),
              ),
            ),
          Expanded(child: _body(context, state, notifier)),
          _Footer(onSettings: () => context.go('/account/notifications/preferences')),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    NotificationsState state,
    NotificationsNotifier notifier,
  ) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorBanner(error: state.error!, onRetry: notifier.refresh),
      );
    }
    if (state.items.isEmpty) {
      return _Empty(onGoHome: () => context.go('/'));
    }
    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.separated(
        itemCount: state.items.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          if (i == state.items.length) {
            if (!state.hasMore) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: state.loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: notifier.loadMore,
                        child: Text('notifications.load_more'.tr()),
                      ),
              ),
            );
          }
          final n = state.items[i];
          return NotificationRow(
            item: n,
            onTap: () => _onTap(context, notifier, n),
          );
        },
      ),
    );
  }

  void _onTap(BuildContext context, NotificationsNotifier notifier, NotificationDto n) {
    if (!n.isRead) notifier.markRead(n.id);
    final link = n.deepLink;
    if (link != null && link.isNotEmpty) context.go(link);
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextButton.icon(
        onPressed: onSettings,
        icon: const Icon(Icons.settings_outlined, size: 18),
        label: Text('notifications.settings_link'.tr()),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onGoHome});
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('notifications.empty'.tr(), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'notifications.empty_sub'.tr(),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onGoHome,
              child: Text('notifications.go_home'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
