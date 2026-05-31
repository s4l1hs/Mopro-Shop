import 'package:mopro/features/notifications/application/notifications_provider.dart';

/// A no-op unread-count notifier (returns 0, starts no poll timer) — use in any
/// widget test that mounts an authed WebHeader / AccountLeftRail so the badge's
/// 60s poll timer doesn't leak past the test.
class StubUnreadCount extends UnreadCountNotifier {
  @override
  int build() => 0;
}

/// Drop this into a ProviderScope's `overrides` to neutralise the badge poller.
final stubUnreadCountOverride =
    unreadNotificationCountProvider.overrideWith(StubUnreadCount.new);
