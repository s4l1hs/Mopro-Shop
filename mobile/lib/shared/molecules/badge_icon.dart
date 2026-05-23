import 'package:flutter/material.dart';

/// Icon with a numeric badge overlay (for cart count in bottom nav).
/// Renders nothing extra when [count] is 0.
class BadgeIcon extends StatelessWidget {
  const BadgeIcon({
    required this.icon,
    required this.count,
    super.key,
  });

  final Widget icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return icon;

    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          top: -4,
          right: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: colorScheme.error,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: TextStyle(
                color: colorScheme.onError,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
