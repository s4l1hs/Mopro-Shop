import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class TrustBar extends StatelessWidget {
  const TrustBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    const items = [
      (Icons.local_shipping_outlined, 'home.trust_free_shipping'),
      (Icons.lock_outline, 'home.trust_secure_payment'),
      (Icons.assignment_return_outlined, 'home.trust_easy_return'),
      (Icons.currency_exchange, 'home.trust_perpetual_cashback'),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items
            .map(
              (item) => _TrustItem(icon: item.$1, label: item.$2.tr()),
            )
            .toList(),
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 26, color: colorScheme.primary),
        const SizedBox(height: 6),
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
