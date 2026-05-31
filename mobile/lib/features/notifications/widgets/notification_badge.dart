import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/notifications/application/notifications_provider.dart';

/// Wraps [child] with an unread-count indicator (top-right). Renders just the
/// child when the count is 0 (or the user is a guest → count stays 0). A dot for
/// 1–9, a "9+" pill above 9.
class NotificationBadge extends ConsumerWidget {
  const NotificationBadge({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationCountProvider);
    if (count <= 0) return child;
    final cs = Theme.of(context).colorScheme;
    final big = count > 9;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -2,
          right: -2,
          child: Semantics(
            label: 'notifications.unread_badge'.tr(args: ['$count']),
            child: Container(
              key: const ValueKey('notification-badge'),
              constraints: BoxConstraints(minWidth: big ? 16 : 8, minHeight: big ? 16 : 8),
              padding: big ? const EdgeInsets.symmetric(horizontal: 4) : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: cs.error,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.surface, width: 1.5),
              ),
              child: big
                  ? Text(
                      '9+',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onError,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
