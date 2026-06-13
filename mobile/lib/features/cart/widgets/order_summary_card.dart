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
/// Coupon (CT-03): "Uygula" applies a seller-funded coupon via the cart
/// notifier's applyCoupon (GET /cart?coupon=); the discounted total + the coupon
/// line come back on the cart DTO and the same code charges at checkout.
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
    final cartState = ref.watch(cartProvider);
    final cart = cartState.cart.valueOrNull;
    final cashback = ref.watch(cartMonthlyCashbackProvider).valueOrNull;

    final subtotalMinor =
        cart?.totalsBySeller.fold<int>(0, (s, t) => s + t.itemsMinor) ?? 0;
    final shippingMinor =
        cart?.totalsBySeller.fold<int>(0, (s, t) => s + t.shippingMinor) ?? 0;
    final totalMinor = cart?.grandTotalMinor ?? 0;
    final couponDiscountMinor = cart?.couponDiscountMinor ?? 0;
    final couponMessage = cart?.couponMessage ?? '';

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
          if (couponDiscountMinor > 0) ...[
            const SizedBox(height: 6),
            _row(
              theme,
              'cart.coupon_discount'.tr(),
              '-${MoneyUtils.formatMinor(couponDiscountMinor)}',
              valueColor: cs.primary,
            ),
          ],
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
                onPressed: cartState.isMutating
                    ? null
                    : () => ref
                        .read(cartProvider.notifier)
                        .applyCoupon(_coupon.text),
                child: Text('cart.apply'.tr()),
              ),
            ],
          ),
          if (couponMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              // A tier-exclusive coupon entered by an ineligible member gets a
              // specific message (membership benefit, migration 0106); every other
              // invalid reason keeps the generic copy.
              couponMessage == 'tier_locked'
                  ? 'membership.coupon_tier_locked'.tr()
                  : 'cart.coupon_invalid'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(color: cs.error),
            ),
          ],
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
