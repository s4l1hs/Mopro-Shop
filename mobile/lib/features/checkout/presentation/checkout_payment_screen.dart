import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';
import 'package:mopro/features/checkout/widgets/checkout_stepper.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: Text('checkout.payment_title'.tr()),
      ),
      body: Column(
        children: [
          const CheckoutStepper(currentStep: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader(title: 'checkout.payment_method'.tr()),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  method: 'card',
                  label: 'checkout.payment_3ds'.tr(),
                  subtitle: 'checkout.payment_3ds_subtitle'.tr(),
                  icon: Icons.credit_card_outlined,
                  selectedMethod: checkoutState.paymentMethod,
                  enabled: true,
                  onSelect: (m) => ref
                      .read(checkoutControllerProvider.notifier)
                      .selectPaymentMethod(m),
                ),
                // PD-05: installment (taksit) picker — card payments only.
                // Interest-free: the total never changes with the count; an
                // unsupported card/count combo is rejected by the bank in 3DS.
                if (checkoutState.paymentMethod == 'card') ...[
                  const SizedBox(height: 12),
                  _InstallmentPicker(
                    selected: checkoutState.installments,
                    onSelect: (n) => ref
                        .read(checkoutControllerProvider.notifier)
                        .selectInstallments(n),
                  ),
                ],
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  method: 'bank_transfer',
                  label: 'checkout.payment_bank_transfer'.tr(),
                  subtitle: 'checkout.payment_coming_soon'.tr(),
                  icon: Icons.account_balance_outlined,
                  selectedMethod: checkoutState.paymentMethod,
                  enabled: false,
                  onSelect: (_) {},
                ),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  method: 'cashback',
                  label: 'checkout.payment_cashback'.tr(),
                  subtitle: 'checkout.payment_coming_soon'.tr(),
                  icon: Icons.card_giftcard_outlined,
                  selectedMethod: checkoutState.paymentMethod,
                  enabled: false,
                  onSelect: (_) {},
                ),
                const SizedBox(height: 20),
                const _SaqANotice(),
                const SizedBox(height: 20),
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
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        total: moneyFmt.format(grandTotal / 100.0),
        canProceed: checkoutState.selectedAddress != null,
        onContinue: () => context.push('/checkout/review'),
      ),
    );
  }
}

class _SaqANotice extends StatelessWidget {
  const _SaqANotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'checkout.secure_payment_title'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(color: cs.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'checkout.secure_payment_body'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Badge(label: 'PCI DSS', icon: Icons.verified_outlined, cs: cs),
              const SizedBox(width: 8),
              _Badge(label: '3D Secure', icon: Icons.security_outlined, cs: cs),
              const SizedBox(width: 8),
              _Badge(label: 'SSL/TLS', icon: Icons.https_outlined, cs: cs),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.icon,
    required this.cs,
  });

  final String label;
  final IconData icon;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// PD-05: taksit choice chips (1 = tek çekim, then 3/6/9/12). Interest-free —
/// no per-option price math is shown because the total does not change.
class _InstallmentPicker extends StatelessWidget {
  const _InstallmentPicker({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'checkout.installments_title'.tr(),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in kInstallmentOptions)
                ChoiceChip(
                  label: Text(
                    n == 1
                        ? 'checkout.installments_single'.tr()
                        : 'checkout.installments_n'
                            .tr(namedArgs: {'count': '$n'}),
                  ),
                  selected: selected == n,
                  onSelected: (_) => onSelect(n),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'checkout.installments_note'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
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

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.method,
    required this.label,
    required this.icon,
    required this.selectedMethod,
    required this.onSelect,
    required this.enabled,
    this.subtitle,
  });

  final String method;
  final String label;
  final String? subtitle;
  final IconData icon;
  final String selectedMethod;
  final bool enabled;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = method == selectedMethod && enabled;
    final cs = Theme.of(context).colorScheme;

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: ListTile(
        leading: Icon(icon, color: isSelected ? cs.primary : null),
        title: Text(label),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              )
            : null,
        // TODO(4e): migrate to RadioGroup (Radio API deprecated Flutter 3.32)
        trailing: Radio<String>(
          value: method,
          groupValue: selectedMethod, // ignore: deprecated_member_use
          onChanged: // ignore: deprecated_member_use
              enabled ? (v) => onSelect(v!) : null,
        ),
        selected: isSelected,
        enabled: enabled,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: isSelected ? cs.primary : cs.outline,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        onTap: enabled ? () => onSelect(method) : null,
      ),
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
    required this.canProceed,
    required this.onContinue,
  });

  final String total;
  final bool canProceed;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: canProceed ? onContinue : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: Text('checkout.continue'.tr()),
        ),
      ),
    );
  }
}
