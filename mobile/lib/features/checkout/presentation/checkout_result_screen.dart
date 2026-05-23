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

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                Icon(
                  failed ? Icons.error_outline : Icons.check_circle_outline,
                  size: 80,
                  color: failed
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  failed
                      ? 'checkout.result_failed_title'.tr()
                      : 'checkout.result_success_title'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  failed
                      ? 'checkout.result_failed_body'.tr()
                      : 'checkout.result_success_body'.tr(
                          namedArgs: {'count': '${orders.length}'},
                        ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
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
    );
  }
}
