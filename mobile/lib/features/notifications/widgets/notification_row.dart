import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/core/utils/relative_time.dart';
import 'package:mopro/features/notifications/data/notification_dto.dart';

/// Renders a single notification. Unread → brand-orange left bar + tinted bg.
class NotificationRow extends StatelessWidget {
  const NotificationRow({required this.item, required this.onTap, super.key});

  final NotificationDto item;
  final VoidCallback onTap;

  IconData get _icon => switch (item.type) {
        NotificationType.orderStatus => Icons.local_shipping_outlined,
        NotificationType.returnUpdate => Icons.assignment_return_outlined,
        NotificationType.security => Icons.shield_outlined,
        NotificationType.marketing => Icons.local_offer_outlined,
        _ => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final unread = !item.isRead;
    final accent = unread ? cs.primary : cs.onSurfaceVariant;

    return Semantics(
      button: true,
      label: item.titleKey.tr(namedArgs: item.bodyParams),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: unread ? cs.primary.withValues(alpha: 0.06) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: unread ? cs.primary : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon, size: 24, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.titleKey.tr(namedArgs: item.bodyParams),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.bodyKey.tr(namedArgs: item.bodyParams),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      relativeTime(item.createdAt),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
