import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';

class CheckoutPaymentScreen extends ConsumerWidget {
  const CheckoutPaymentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkoutState = ref.watch(checkoutControllerProvider);
    final cartState = ref.watch(cartProvider);
    final moneyFmt = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );

    final grandTotal = cartState.cart.valueOrNull?.grandTotalMinor ?? 0;

    ref.listen(checkoutControllerProvider, (prev, next) {
      if (next.response != null && prev?.response == null) {
        if (next.response!.requires3ds) {
          context.push('/checkout/3ds');
        } else {
          context.go('/checkout/result');
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('checkout.payment_title'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(title: 'checkout.payment_method'.tr()),
          const SizedBox(height: 8),
          _PaymentMethodTile(
            method: 'card',
            label: 'checkout.payment_card'.tr(),
            icon: Icons.credit_card,
            selectedMethod: checkoutState.paymentMethod,
            onSelect: (m) => ref
                .read(checkoutControllerProvider.notifier)
                .selectPaymentMethod(m),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'checkout.order_summary'.tr()),
          const SizedBox(height: 8),
          _OrderSummaryRow(
            label: 'checkout.subtotal'.tr(),
            value: moneyFmt.format(grandTotal / 100.0),
          ),
          const Divider(height: 24),
          _OrderSummaryRow(
            label: 'checkout.total'.tr(),
            value: moneyFmt.format(grandTotal / 100.0),
            isTotal: true,
          ),
          if (checkoutState.error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(
              error: checkoutState.error!,
              onRetry: () =>
                  ref.read(checkoutControllerProvider.notifier).placeOrder(),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _BottomBar(
        total: moneyFmt.format(grandTotal / 100.0),
        isLoading: checkoutState.isInitiating,
        canProceed: checkoutState.canProceed,
        onPlace: () =>
            ref.read(checkoutControllerProvider.notifier).placeOrder(),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.method,
    required this.label,
    required this.icon,
    required this.selectedMethod,
    required this.onSelect,
  });

  final String method;
  final String label;
  final IconData icon;
  final String selectedMethod;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = method == selectedMethod;
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, color: isSelected ? cs.primary : null),
      title: Text(label),
      trailing: Radio<String>(
        value: method,
        groupValue: selectedMethod,
        onChanged: (v) => onSelect(v!),
      ),
      selected: isSelected,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected ? cs.primary : cs.outline,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      onTap: () => onSelect(method),
    );
  }
}

class _OrderSummaryRow extends StatelessWidget {
  const _OrderSummaryRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  final String label;
  final String value;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    final style = isTotal
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            )
        : Theme.of(context).textTheme.bodyMedium;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.total,
    required this.isLoading,
    required this.canProceed,
    required this.onPlace,
  });

  final String total;
  final bool isLoading;
  final bool canProceed;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: canProceed && !isLoading ? onPlace : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'checkout.place_order'.tr(namedArgs: {'amount': total}),
                ),
        ),
      ),
    );
  }
}
