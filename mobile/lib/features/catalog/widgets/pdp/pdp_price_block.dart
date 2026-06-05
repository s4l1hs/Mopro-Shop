import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/design/widgets/discount_pill.dart';
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
              // P-006: shared DiscountPill (was brand-orange here, a red hex on
              // the product card — now one destructive token on both surfaces).
              DiscountPill(percent: _discountPct),
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
        // P-030: show the lowest-30-day price only when the current price is NOT
        // the 30-day low (lowest < price) — the consumer-protection signal. Today
        // lowest == price for every variant (no price-update lifecycle yet), so it
        // stays dark until a seller changes a price (P-032).
        if (lowestIn30DaysMinor != null && lowestIn30DaysMinor! < priceMinor) ...[
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
