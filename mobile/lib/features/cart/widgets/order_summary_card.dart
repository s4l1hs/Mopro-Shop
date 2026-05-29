import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/utils/money.dart';

/// Tablet/desktop order-summary card for the cart's right column. Reads
/// [cartProvider] + [cartMonthlyCashbackProvider] (no new providers) and renders
/// subtotal / shipping / estimated cashback / total, a coupon input, and the
/// "Sepeti Onayla" CTA. [onCheckout] is wired by the screen.
///
/// Coupon application is a placeholder (no coupon backend exists yet) — the
/// "Uygula" button is inert; see REPORT §4.
class OrderSummaryCard extends ConsumerStatefulWidget {
  const OrderSummaryCard({required this.onCheckout, super.key});

  final VoidCallback? onCheckout;

  @override
  ConsumerState<OrderSummaryCard> createState() => _OrderSummaryCardState();
}

class _OrderSummaryCardState extends ConsumerState<OrderSummaryCard> {
  final _coupon = TextEditingController();

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cart = ref.watch(cartProvider).cart.valueOrNull;
    final cashback = ref.watch(cartMonthlyCashbackProvider).valueOrNull;

    final subtotalMinor =
        cart?.totalsBySeller.fold<int>(0, (s, t) => s + t.itemsMinor) ?? 0;
    final shippingMinor =
        cart?.totalsBySeller.fold<int>(0, (s, t) => s + t.shippingMinor) ?? 0;
    final totalMinor = cart?.grandTotalMinor ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'cart.order_summary'.tr(),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _row(theme, 'cart.subtotal'.tr(), MoneyUtils.formatMinor(subtotalMinor)),
          const SizedBox(height: 6),
          _row(
            theme,
            'cart.shipping'.tr(),
            shippingMinor == 0
                ? 'cart.shipping_free'.tr()
                : MoneyUtils.formatMinor(shippingMinor),
          ),
          if (cashback != null && cashback > 0) ...[
            const SizedBox(height: 6),
            _row(
              theme,
              'cart.estimated_earnings'.tr(),
              MoneyUtils.formatMinor(cashback, currency: 'TRY_COIN'),
              valueColor: cs.primary,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          _row(
            theme,
            'cart.total'.tr(),
            MoneyUtils.formatMinor(totalMinor),
            bold: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _coupon,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'cart.coupon_code'.tr(),
                      border: const OutlineInputBorder(),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () {}, // coupon backend not wired (REPORT §4)
                child: Text('cart.apply'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: widget.onCheckout,
              child: Text('cart.confirm_cart'.tr()),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'cart.summary_helper'.tr(),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) {
    final base = bold ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium;
    final weight = bold ? FontWeight.bold : null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: base?.copyWith(fontWeight: weight)),
        Text(value, style: base?.copyWith(fontWeight: weight, color: valueColor)),
      ],
    );
  }
}
