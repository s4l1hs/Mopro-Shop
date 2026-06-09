import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/features/notifications/widgets/notification_badge.dart';

/// Header affordance (HP-06): a bell icon overlaid with the live unread badge
/// ([NotificationBadge], driven by `unreadNotificationCountProvider`). Tapping
/// routes to the inbox via [onTap] — the caller supplies navigation so each
/// header keeps its own convention (mirrors `_HeaderIconButton`).
///
/// Guest-safe by construction: [NotificationBadge] renders just the bell at
/// count 0, and the provider is 0 for unauthenticated users — so a guest sees
/// the icon (like cart/favorites) but never a personal badge.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    required this.onTap,
    this.size = 22,
    this.hitTarget = 44,
    super.key,
  });

  /// Navigation to the inbox route, supplied by the mounting header.
  final VoidCallback onTap;

  /// Icon glyph size.
  final double size;

  /// Square hit-target side (≥ 44 for touch accessibility).
  final double hitTarget;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = 'notifications.bell_tooltip'.tr();
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: onTap,
        radius: hitTarget / 2,
        child: SizedBox(
          width: hitTarget,
          height: hitTarget,
          child: Center(
            child: Semantics(
              button: true,
              label: label,
              child: NotificationBadge(
                child: Icon(
                  Icons.notifications_none_rounded,
                  size: size,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
