import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/utils/money.dart';
import 'package:mopro_api/mopro_api.dart';

/// Condensed sticky buy-bar for the wide (tablet/desktop) PDP (PD-09): slides in
/// at the viewport top once the buy-box column scrolls out of view, keeping
/// thumbnail + title + price + "Sepete Ekle" reachable while reading
/// tabs/reviews. Distinct from the mobile `PdpStickyCta` bottom bar (the
/// composition test asserts desktop has no PdpStickyCta) and deliberately does
/// NOT touch the sticky-gallery translate mechanics.
class PdpStickyBuyBar extends StatelessWidget {
  const PdpStickyBuyBar({
    required this.visible,
    required this.title,
    required this.selectedVariant,
    required this.isMutating,
    required this.onAddToCart,
    this.imageUrl,
    super.key,
  });

  /// Whether the bar is shown (the buy-box has scrolled out of view).
  final bool visible;
  final String title;
  final Variant? selectedVariant;
  final bool isMutating;
  final VoidCallback onAddToCart;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final v = selectedVariant;

    // Offstage while hidden: not painted, not hit-testable, and skipped by
    // default widget-test finders (the desktop composition test keeps finding
    // exactly one add-to-cart CTA at scroll origin). On reveal, AnimatedSlide
    // runs the (0,-1) → 0 entrance.
    return Offstage(
      offstage: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Material(
          color: cs.surface,
          elevation: 3,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                if (imageUrl != null && imageUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          ColoredBox(color: cs.surfaceContainerHighest),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 16),
                if (v != null) ...[
                  Text(
                    MoneyUtils.formatMinor(v.priceMinor),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                FilledButton(
                  onPressed: v != null && !isMutating ? onAddToCart : null,
                  child: isMutating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('product.add_to_cart'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
