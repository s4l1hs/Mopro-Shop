import 'package:flutter/material.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/utils/money.dart';

class PriceDisplay extends StatelessWidget {
  const PriceDisplay({
    required this.priceMinor,
    this.originalPriceMinor,
    this.currency = 'TRY',
    this.size = PriceDisplaySize.md,
    super.key,
  });

  final int priceMinor;
  final int? originalPriceMinor;
  final String currency;
  final PriceDisplaySize size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final original = originalPriceMinor;

    final (priceStyle, originalStyle) = switch (size) {
      PriceDisplaySize.sm => (
          theme.textTheme.labelLarge?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
          ),
          theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      PriceDisplaySize.md => (
          theme.textTheme.titleMedium?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
          ),
          theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      PriceDisplaySize.lg => (
          theme.textTheme.headlineSmall?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w700,
          ),
          theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
          ),
        ),
    };

    final hasDiscount =
        original != null && original > priceMinor && original > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          MoneyUtils.formatMinor(priceMinor, currency: currency),
          style: priceStyle,
        ),
        if (hasDiscount) ...[
          const SizedBox(width: 6),
          Text(
            MoneyUtils.formatMinor(original, currency: currency),
            style: originalStyle,
          ),
          const SizedBox(width: 4),
          _DiscountBadge(
            original: original,
            current: priceMinor,
            destructive: cs.error,
            onDestructive: cs.onError,
          ),
        ],
      ],
    );
  }
}

enum PriceDisplaySize { sm, md, lg }

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({
    required this.original,
    required this.current,
    required this.destructive,
    required this.onDestructive,
  });

  final int original;
  final int current;
  final Color destructive;
  final Color onDestructive;

  @override
  Widget build(BuildContext context) {
    final pct = ((original - current) / original * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: destructive,
        borderRadius: BorderRadius.circular(MoproTokens.radiusSm),
      ),
      child: Text(
        '-%$pct',
        style: TextStyle(
          color: onDestructive,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}
