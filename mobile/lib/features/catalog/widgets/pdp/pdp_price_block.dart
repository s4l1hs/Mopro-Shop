import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/utils/money.dart';

/// Price block for the PDP buy-box: brand-orange current price, optional
/// strikethrough original + discount-% pill, optional "lowest in 30 days" hint.
///
/// [originalPriceMinor] and [lowestIn30DaysMinor] are nullable because the
/// catalog API does not expose them yet; when null the corresponding row is
/// simply omitted (today's behaviour). Extracted from the PDP buy-box so the
/// mobile and desktop layouts share one price renderer.
class PdpPriceBlock extends StatelessWidget {
  const PdpPriceBlock({
    required this.priceMinor,
    this.currency,
    this.originalPriceMinor,
    this.lowestIn30DaysMinor,
    super.key,
  });

  final int priceMinor;
  final String? currency;
  final int? originalPriceMinor;
  final int? lowestIn30DaysMinor;

  bool get _hasDiscount =>
      originalPriceMinor != null && originalPriceMinor! > priceMinor;

  int get _discountPct =>
      (((originalPriceMinor! - priceMinor) * 100) / originalPriceMinor!).round();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasDiscount)
          Row(
            children: [
              Text(
                MoneyUtils.formatMinor(originalPriceMinor!),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '%$_discountPct',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        if (_hasDiscount) const SizedBox(height: 2),
        Text(
          MoneyUtils.formatMinor(priceMinor),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: cs.primary,
          ),
        ),
        if (lowestIn30DaysMinor != null) ...[
          const SizedBox(height: 4),
          Text(
            'product.lowest_30d'.tr(
              namedArgs: {'price': MoneyUtils.formatMinor(lowestIn30DaysMinor!)},
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
