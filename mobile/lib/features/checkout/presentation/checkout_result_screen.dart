import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';

class CheckoutResultScreen extends ConsumerWidget {
  const CheckoutResultScreen({this.failed = false, super.key});

  final bool failed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkoutState = ref.watch(checkoutControllerProvider);
    final orders = checkoutState.response?.orders ?? [];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Clear cart and reset checkout state on first success render
    ref.listen(checkoutControllerProvider, (prev, _) {
      if (prev == null && !failed && orders.isNotEmpty) {
        ref.read(cartProvider.notifier).clear();
      }
    });

    // Compute cashback activation date: first order created_at + 3 business days (approx 5 calendar days)
    final firstOrder = orders.isNotEmpty ? orders.first : null;
    final cashbackDate = firstOrder?.createdAt.add(const Duration(days: 5));

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          // Anti-overflow: center the result when the viewport is tall enough,
          // but scroll instead of overflowing on short/landscape screens or at
          // max text scale (the Spacers + fixed buttons would otherwise blow the
          // column height past the viewport → RenderFlex overflow).
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                Icon(
                  failed ? Icons.error_outline : Icons.check_circle_outline,
                  size: 80,
                  color: failed ? cs.error : cs.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  failed
                      ? 'checkout.result_failed_title'.tr()
                      : 'checkout.result_success_title'.tr(),
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (!failed && orders.isNotEmpty) ...[
                  Text(
                    'checkout.result_order_numbers'.tr(
                      namedArgs: {
                        'numbers': orders.map((o) => '#${o.id}').join(', '),
                      },
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  failed
                      ? 'checkout.result_failed_body'.tr()
                      : 'checkout.result_success_body'.tr(
                          namedArgs: {'count': '${orders.length}'},
                        ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!failed && cashbackDate != null) ...[
                  const SizedBox(height: 16),
                  _CashbackActivationBadge(
                    date: cashbackDate,
                    theme: theme,
                    cs: cs,
                  ),
                ],
                const Spacer(),
                if (failed) ...[
                  OutlinedButton(
                    onPressed: () => context.go('/cart'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text('checkout.back_to_cart'.tr()),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: () {
                    ref.read(checkoutControllerProvider.notifier).reset();
                    if (!failed) {
                      ref.read(cartProvider.notifier).refresh();
                    }
                    context.go('/orders');
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(
                    failed
                        ? 'checkout.retry'.tr()
                        : 'checkout.view_orders'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    ref.read(checkoutControllerProvider.notifier).reset();
                    context.go('/');
                  },
                  child: Text('checkout.continue_shopping'.tr()),
                ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CashbackActivationBadge extends StatelessWidget {
  const _CashbackActivationBadge({
    required this.date,
    required this.theme,
    required this.cs,
  });

  final DateTime date;
  final ThemeData theme;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.card_giftcard_outlined, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'checkout.cashback_activation_date'
                  .tr(namedArgs: {'date': dateStr}),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.primary),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
