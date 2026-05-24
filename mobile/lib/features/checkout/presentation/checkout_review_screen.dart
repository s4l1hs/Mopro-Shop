import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';
import 'package:mopro/features/checkout/widgets/checkout_stepper.dart';

class CheckoutReviewScreen extends ConsumerStatefulWidget {
  const CheckoutReviewScreen({super.key});

  @override
  ConsumerState<CheckoutReviewScreen> createState() =>
      _CheckoutReviewScreenState();
}

class _CheckoutReviewScreenState extends ConsumerState<CheckoutReviewScreen> {
  bool _consentSales = false;
  bool _consentDistanceContract = false;

  @override
  void initState() {
    super.initState();
    // Listen for checkout result to navigate
  }

  @override
  Widget build(BuildContext context) {
    final checkoutState = ref.watch(checkoutControllerProvider);
    final cartState = ref.watch(cartProvider);
    final moneyFmt = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );
    final grandTotal = cartState.cart.valueOrNull?.grandTotalMinor ?? 0;
    final lines = cartState.cart.valueOrNull?.lines ?? [];

    ref.listen(checkoutControllerProvider, (prev, next) {
      if (next.response != null && prev?.response == null) {
        if (next.response!.requires3ds) {
          context.push('/checkout/3ds');
        } else {
          context.go('/checkout/result');
        }
      }
    });

    final canPlace = _consentSales &&
        _consentDistanceContract &&
        checkoutState.canProceed;

    return Scaffold(
      appBar: AppBar(
        title: Text('checkout.review_title'.tr()),
      ),
      body: Column(
        children: [
          const CheckoutStepper(currentStep: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader(title: 'checkout.review_items'.tr()),
                const SizedBox(height: 8),
                ...lines.map(
                  (line) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            line.title,
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${line.qty}× ${moneyFmt.format(line.priceMinor / 100.0)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 24),
                _SummaryRow(
                  label: 'checkout.total'.tr(),
                  value: moneyFmt.format(grandTotal / 100.0),
                  isTotal: true,
                ),
                const SizedBox(height: 24),
                _ConsentCheckbox(
                  value: _consentSales,
                  label: 'checkout.consent_sales'.tr(),
                  onChanged: (v) => setState(() => _consentSales = v ?? false),
                ),
                const SizedBox(height: 8),
                _ConsentCheckbox(
                  value: _consentDistanceContract,
                  label: 'checkout.consent_distance_contract'.tr(),
                  onChanged: (v) =>
                      setState(() => _consentDistanceContract = v ?? false),
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
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        total: moneyFmt.format(grandTotal / 100.0),
        isLoading: checkoutState.isInitiating,
        canPlace: canPlace,
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
  Widget build(BuildContext context) =>
      Text(title, style: Theme.of(context).textTheme.titleSmall);
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
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
        ? Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}

class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: value, onChanged: onChanged),
        const SizedBox(width: 4),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.total,
    required this.isLoading,
    required this.canPlace,
    required this.onPlace,
  });

  final String total;
  final bool isLoading;
  final bool canPlace;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: canPlace && !isLoading ? onPlace : null,
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
