import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/design/widgets/discount_pill.dart';
import 'package:mopro/utils/money.dart';

/// Price block for the PDP buy-box: brand-orange current price, optional
/// strikethrough original + discount-% pill, optional "lowest in 30 days" hint.
///
/// [originalPriceMinor] and [lowestIn30DaysMinor] are nullable because the
/// catalog API omits them when the variant was never marked down / has no
/// in-window price history; when null the corresponding row is simply omitted.
/// Extracted from the PDP buy-box so the mobile and desktop layouts share one
/// price renderer.
class PdpPriceBlock extends StatelessWidget {
  const PdpPriceBlock({
    required this.priceMinor,
    this.currency,
    this.originalPriceMinor,
    this.lowestIn30DaysMinor,
    this.basketDiscountPct,
    super.key,
  });

  final int priceMinor;
  final String? currency;
  final int? originalPriceMinor;
  final int? lowestIn30DaysMinor;

  /// PD-03: the CT-09 seller-funded "Sepette %X İndirim" — the SAME snapshot the
  /// order charges (display==charge). Null/0 → no pill.
  final int? basketDiscountPct;

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
        // PD-03: "Sepette %X İndirim" — the CT-09 charged basket discount, surfaced
        // on the PDP (display==charge; same products.basket_discount_pct).
        if (basketDiscountPct != null && basketDiscountPct! > 0) ...[
          const SizedBox(height: 4),
          _BasketDiscountPill(percent: basketDiscountPct!),
        ],
        // P-030: show the lowest-30-day price only on a discounted variant whose
        // current price is NOT the 30-day low — the consumer-protection signal.
        // The `_hasDiscount &&` guard aligns this with the product card's
        // `hasDiscount && lowest_30d < price` gate (PDP-strikethrough): a lowest-30d
        // line without a strikethrough above it read as orphaned. Today lowest ==
        // price for every variant (no price-update lifecycle yet), so it stays
        // dark until a seller changes a price (P-032).
        if (_hasDiscount &&
            lowestIn30DaysMinor != null &&
            lowestIn30DaysMinor! < priceMinor) ...[
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

/// "Sepette %X İndirim" pill (mirrors the product card's), brand-orange tint.
class _BasketDiscountPill extends StatelessWidget {
  const _BasketDiscountPill({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'product.basket_discount'.tr(namedArgs: {'pct': '$percent'}),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );
  }
}
