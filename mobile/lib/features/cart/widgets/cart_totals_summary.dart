import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/utils/money.dart';

class CartTotalsSummary extends StatelessWidget {
  const CartTotalsSummary({
    required this.cart,
    required this.onCheckout,
    this.cashbackMonthlyMinor,
    super.key,
  });

  final CartDto cart;
  final VoidCallback? onCheckout;
  final int? cashbackMonthlyMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fmt = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );

    final grandTotal = fmt.format(cart.grandTotalMinor / 100.0);
    final itemCount = cart.lines.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cart.isAboveTotalLimit)
            _WarningChip(
              message: 'cart.warning_total_limit'.tr(),
              colorScheme: colorScheme,
            ),
          if (cart.isAtItemLimit)
            _WarningChip(
              message: 'cart.warning_item_limit'.tr(),
              colorScheme: colorScheme,
            ),
          if (cashbackMonthlyMinor != null && cashbackMonthlyMinor! > 0) ...[
            _CashbackSummaryBox(
              monthly: cashbackMonthlyMinor!,
              colorScheme: colorScheme,
              theme: theme,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'cart.item_count'
                        .tr(namedArgs: {'count': '$itemCount'}),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    grandTotal,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'cart.kdv_included'.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: onCheckout,
                icon: const Icon(Icons.payment_outlined),
                label: Text('cart.proceed_to_checkout'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CashbackSummaryBox extends StatelessWidget {
  const _CashbackSummaryBox({
    required this.monthly,
    required this.colorScheme,
    required this.theme,
  });

  final int monthly;
  final ColorScheme colorScheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.05),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.card_giftcard_outlined,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'cart.cashback_monthly'
                      .tr(namedArgs: {'amount': MoneyUtils.formatMinor(monthly, currency: 'TRY_COIN')}),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'cart.cashback_perpetual'.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningChip extends StatelessWidget {
  const _WarningChip({
    required this.message,
    required this.colorScheme,
  });

  final String message;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
