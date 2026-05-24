import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/checkout/application/checkout_controller.dart';
import 'package:mopro/features/checkout/widgets/checkout_stepper.dart';

class CheckoutPaymentScreen extends ConsumerStatefulWidget {
  const CheckoutPaymentScreen({super.key});

  @override
  ConsumerState<CheckoutPaymentScreen> createState() =>
      _CheckoutPaymentScreenState();
}

class _CheckoutPaymentScreenState
    extends ConsumerState<CheckoutPaymentScreen> {
  final _cardNumberCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _cvvCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _cardBrand = '';

  @override
  void dispose() {
    _cardNumberCtrl.dispose();
    _expiryCtrl.dispose();
    _cvvCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  String _detectBrand(String number) {
    final n = number.replaceAll(' ', '');
    if (n.startsWith('4')) return 'Visa';
    if (RegExp(r'^5[1-5]').hasMatch(n)) return 'Mastercard';
    if (RegExp(r'^3[47]').hasMatch(n)) return 'Amex';
    if (n.startsWith('6')) return 'Troy';
    return '';
  }

  bool _luhnCheck(String number) {
    final n = number.replaceAll(' ', '');
    if (n.isEmpty) return false;
    var sum = 0;
    var isAlternate = false;
    for (var i = n.length - 1; i >= 0; i--) {
      var digit = int.tryParse(n[i]) ?? 0;
      if (isAlternate) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
      isAlternate = !isAlternate;
    }
    return sum % 10 == 0;
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

    return Scaffold(
      appBar: AppBar(
        title: Text('checkout.payment_title'.tr()),
      ),
      body: Column(
        children: [
          const CheckoutStepper(currentStep: 1),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
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
                  const SizedBox(height: 20),
                  _SectionHeader(title: 'checkout.card_details'.tr()),
                  const SizedBox(height: 12),
                  _CardNumberField(
                    controller: _cardNumberCtrl,
                    brand: _cardBrand,
                    onChanged: (v) {
                      setState(() => _cardBrand = _detectBrand(v));
                    },
                    luhnValidator: _luhnCheck,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ExpiryField(controller: _expiryCtrl),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CvvField(controller: _cvvCtrl),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _holderCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'checkout.card_holder'.tr(),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'checkout.card_holder_required'.tr()
                        : null,
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
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        total: moneyFmt.format(grandTotal / 100.0),
        canProceed: checkoutState.selectedAddressId != null,
        onContinue: () {
          if (_formKey.currentState?.validate() ?? false) {
            context.push('/checkout/review');
          }
        },
      ),
    );
  }
}

class _CardNumberField extends StatelessWidget {
  const _CardNumberField({
    required this.controller,
    required this.brand,
    required this.onChanged,
    required this.luhnValidator,
  });

  final TextEditingController controller;
  final String brand;
  final ValueChanged<String> onChanged;
  final bool Function(String) luhnValidator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _CardNumberFormatter(),
      ],
      maxLength: 19,
      decoration: InputDecoration(
        labelText: 'checkout.card_number'.tr(),
        border: const OutlineInputBorder(),
        counterText: '',
        suffixText: brand.isEmpty ? null : brand,
        suffixStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
      onChanged: onChanged,
      validator: (v) {
        if (v == null || v.isEmpty) return 'checkout.card_number_required'.tr();
        if (!luhnValidator(v)) return 'checkout.card_number_invalid'.tr();
        return null;
      },
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue newVal,
  ) {
    final digits = newVal.text.replaceAll(' ', '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _ExpiryField extends StatelessWidget {
  const _ExpiryField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _ExpiryFormatter(),
      ],
      maxLength: 5,
      decoration: InputDecoration(
        labelText: 'checkout.card_expiry'.tr(),
        hintText: 'MM/YY',
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      validator: (v) {
        if (v == null || v.length < 5) return 'checkout.card_expiry_required'.tr();
        final parts = v.split('/');
        if (parts.length != 2) return 'checkout.card_expiry_invalid'.tr();
        final month = int.tryParse(parts[0]) ?? 0;
        if (month < 1 || month > 12) return 'checkout.card_expiry_invalid'.tr();
        return null;
      },
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue newVal,
  ) {
    final digits = newVal.text.replaceAll('/', '');
    if (digits.length >= 2) {
      final text = '${digits.substring(0, 2)}/${digits.substring(2)}';
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    return newVal;
  }
}

class _CvvField extends StatelessWidget {
  const _CvvField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 4,
      obscureText: true,
      decoration: InputDecoration(
        labelText: 'checkout.card_cvv'.tr(),
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      validator: (v) {
        if (v == null || v.length < 3) return 'checkout.card_cvv_required'.tr();
        return null;
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleSmall);
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
