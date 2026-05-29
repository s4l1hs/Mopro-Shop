import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/utils/money.dart';
import 'package:mopro_api/mopro_api.dart';

/// Mobile sticky bottom CTA: selected-variant price + a full-width
/// "Sepete Ekle" button. Disabled while no variant is selected or a cart
/// mutation is in flight. Extracted verbatim from the PDP so the mobile layout
/// keeps it and the tablet/desktop layouts can omit it (their buy-box column
/// carries its own CTA).
class PdpStickyCta extends StatelessWidget {
  const PdpStickyCta({
    required this.selectedVariant,
    required this.isMutating,
    required this.onAddToCart,
    super.key,
  });

  final Variant? selectedVariant;
  final bool isMutating;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            if (selectedVariant != null) ...[
              Text(
                MoneyUtils.formatMinor(selectedVariant!.priceMinor),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: FilledButton(
                onPressed:
                    selectedVariant != null && !isMutating ? onAddToCart : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: isMutating
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('product.add_to_cart'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
