import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/design/widgets/discount_pill.dart';
import 'package:mopro/design/widgets/responsive_network_image.dart';
import 'package:mopro/features/catalog/widgets/cashback_chip.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:mopro/utils/count_format.dart';
import 'package:mopro/utils/money.dart';
import 'package:mopro/widgets/skeleton_box.dart';
import 'package:mopro_api/mopro_api.dart';

/// Canonical Trendyol-style product card.
/// Square image · heart top-right · brand · title · price + optional
/// strikethrough original price + discount % badge · optional rating chip ·
/// cashback chip.
///
/// [originalPriceMinor], [discountPct], [ratingAvg], and [ratingCount] come
/// from the backend's enriched JSON (POST /products/batch, GET /products);
/// when the generated DTO doesn't surface them, callers may pass them via
/// these optional named params.
class ProductCard extends ConsumerWidget {
  const ProductCard({
    required this.product,
    required this.onTap,
    super.key,
    this.originalPriceMinor,
    this.discountPct,
    this.ratingAvg,
    this.ratingCount = 0,
    this.priceOverride,
    this.basketDiscountPct,
    this.isBestseller = false,
    this.isOfficialSeller = false,
  });

  final ProductSummary product;
  final VoidCallback onTap;
  final int? originalPriceMinor;
  final int? discountPct;
  final double? ratingAvg;
  final int ratingCount;

  /// "Sepette %X İndirim" basket-discount: the extra percentage knocked off at
  /// the cart. Null → no pill (the common case until the backend emits it).
  final int? basketDiscountPct;

  /// When true, stamps a "Çok Satan" ribbon over the image (Trendyol-style).
  final bool isBestseller;

  /// When true, stamps a "Resmi Satıcı" official/verified-seller badge (PLP-17).
  final bool isOfficialSeller;

  /// Flash-deal override: when set, this is shown as the (brand-orange) price
  /// and the product's regular `priceMinor` becomes the strikethrough original
  /// (discount % is recomputed from the two). Used by FlashDealsRail.
  final int? priceOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isFav = ref.watch(isFavoriteProvider(product.id));
    // Flash override substitutes the flash price for the main price and uses
    // the regular price as the strikethrough original.
    final effectivePrice = priceOverride ?? product.priceMinor;
    final effectiveOriginal =
        priceOverride != null ? product.priceMinor : originalPriceMinor;
    final effectiveDiscountPct = (priceOverride != null &&
            effectiveOriginal != null &&
            effectiveOriginal > effectivePrice &&
            effectiveOriginal > 0)
        ? ((effectiveOriginal - effectivePrice) * 100) ~/ effectiveOriginal
        : discountPct;
    final priceStr = MoneyUtils.formatMinor(effectivePrice);
    final hasDiscount = effectiveOriginal != null &&
        effectiveOriginal > effectivePrice &&
        (effectiveDiscountPct ?? 0) > 0;
    final hasRating = ratingCount > 0 && ratingAvg != null;
    // P-030: "lowest price in 30 days" compliance line (TR 6502 / EU Omnibus).
    // Shown only when a reduction is announced (hasDiscount) AND the current
    // price is not the 30-day low. lowest_30d <= price always, so `<` means it
    // was cheaper earlier in the window. Suppressed on flash cards (the override
    // price is not the regular-price history). Today lowest_30d == price for
    // every product (no price-update lifecycle yet → P-032), so this stays dark
    // until prices move.
    final low30d = product.lowest30dPriceMinor;
    final showLowest30d = priceOverride == null &&
        hasDiscount &&
        low30d != null &&
        low30d < effectivePrice;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image with heart overlay ────────────────────────────────────
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'product-image-${product.id}',
                    child: _ProductImage(imageUrl: product.coverImageUrl, cs: cs),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _HeartButton(
                      isFav: isFav,
                      onToggle: () {
                        // Guests can toggle locally; server sync happens on auth.
                        ref.read(favoritesProvider.notifier).toggle(product.id);
                      },
                    ),
                  ),
                  // P-004: favorites social-proof count (the global server count,
                  // no optimistic update). Bottom-left, distinct from the toggle.
                  if (formatCompactCount(product.favoritesCount ?? 0).isNotEmpty)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child:
                          _FavoritesCountBadge(count: product.favoritesCount ?? 0),
                    ),
                  // Top-left badge stack (off the text column so they can't
                  // overflow tight cells): the "Çok Satan" bestseller stamp
                  // (G-3) above the free-shipping ("Kargo Bedava") badge (P-009).
                  if (isOfficialSeller ||
                      isBestseller ||
                      (product.freeShipping ?? false))
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isOfficialSeller) const _OfficialSellerBadge(),
                          if (isOfficialSeller &&
                              (isBestseller || (product.freeShipping ?? false)))
                            const SizedBox(height: 4),
                          if (isBestseller) const _BestsellerBadge(),
                          if (isBestseller && (product.freeShipping ?? false))
                            const SizedBox(height: 4),
                          if (product.freeShipping ?? false)
                            const _FreeShippingBadge(),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // ── Text content ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (product.brand.isNotEmpty)
                    Text(
                      product.brand.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  if (hasRating) ...[
                    const SizedBox(height: 4),
                    _RatingChip(avg: ratingAvg!, count: ratingCount),
                  ],
                  const SizedBox(height: 6),
                  // Price block: optional strikethrough original + discount %
                  // badge above the current price.
                  if (hasDiscount) ...[
                    Row(
                      children: [
                        Text(
                          MoneyUtils.formatMinor(effectiveOriginal),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // P-006: shared DiscountPill (was a one-off red hex here,
                        // brand-orange on the PDP — now one destructive token).
                        DiscountPill(percent: effectiveDiscountPct!),
                      ],
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    priceStr,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      // P-005: theme-aware primary (was hardcoded primaryLight,
                      // which rendered the light-mode orange on the dark card).
                      color: cs.primary,
                    ),
                  ),
                  // G-3: "Sepette %X İndirim" basket-discount pill, brand-orange,
                  // directly under the price. Hidden until a non-null pct is
                  // passed (backend signal pending).
                  if (basketDiscountPct != null) ...[
                    const SizedBox(height: 4),
                    _BasketDiscountPill(percent: basketDiscountPct!),
                  ],
                  if (showLowest30d) ...[
                    const SizedBox(height: 2),
                    Text(
                      'product.lowest_30d'.tr(
                        namedArgs: {'price': MoneyUtils.formatMinor(low30d)},
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  CashbackChip(
                    monthlyCoinMinor:
                        product.cashbackPreview.monthlyCoinMinor,
                    currency: product.cashbackPreview.currency,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeartButton extends StatelessWidget {
  const _HeartButton({required this.isFav, required this.onToggle});
  final bool isFav;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Icon(
          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 18,
          color:
              isFav ? MoproTokens.primaryLight : const Color(0xFF888888),
        ),
      ),
    );
  }
}

class _FreeShippingBadge extends StatelessWidget {
  const _FreeShippingBadge();

  @override
  Widget build(BuildContext context) {
    // Same translucent-dark overlay style as the favorites badge: white on a
    // dark scrim is legible over any product image + AA-safe in both themes
    // (no new design token; a green treatment is a future polish).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_shipping_outlined, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            'plp.free_shipping'.tr(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Çok Satan" bestseller stamp — a compact solid brand-orange ribbon over the
/// image's top-left (G-3). Fixed brand orange + white text reads consistently
/// over any product photo in both themes (same rationale as _FreeShippingBadge).
class _BestsellerBadge extends StatelessWidget {
  const _BestsellerBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: MoproTokens.primaryLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            'product.bestseller'.tr(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Resmi Satıcı" official/verified-seller badge — a compact solid blue ribbon
/// with a verified check (PLP-17). Fixed blue + white reads over any product
/// photo in both themes (same rationale as the other image badges).
class _OfficialSellerBadge extends StatelessWidget {
  const _OfficialSellerBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            'product.official_seller'.tr(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Sepette %X İndirim" basket-discount pill — brand-orange, high-visibility,
/// directly under the price (G-3). Theme-aware via `cs.primary` (P-005). Lives
/// in the bounded text column, so the text ellipsizes rather than overflowing
/// at tight 375dp cells.
class _BasketDiscountPill extends StatelessWidget {
  const _BasketDiscountPill({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'product.basket_discount'.tr(namedArgs: {'pct': '$percent'}),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _FavoritesCountBadge extends StatelessWidget {
  const _FavoritesCountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        // Translucent dark scrim keeps white text legible over any image
        // (same one-off-overlay style as the heart button's white circle).
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.favorite_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            formatCompactCount(count),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl, required this.cs});
  final String? imageUrl;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) return _placeholder;
    return ResponsiveNetworkImage(
      imageUrl: imageUrl!,
      placeholder: (_, __) => _placeholder,
      errorWidget: (_, __, ___) => _placeholder,
    );
  }

  Widget get _placeholder => ColoredBox(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.image_outlined, size: 40, color: cs.outlineVariant),
      );
}

/// Skeleton placeholder used while loading a product grid.
class SkeletonProductCard extends StatelessWidget {
  const SkeletonProductCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AspectRatio(
            aspectRatio: 1,
            child: SkeletonBox(width: double.infinity, height: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBox(width: 60, height: 10),
                const SizedBox(height: 4),
                const SkeletonBox(width: double.infinity, height: 10),
                const SizedBox(height: 2),
                SkeletonBox(
                  width: MediaQuery.of(context).size.width * 0.25,
                  height: 10,
                ),
                const SizedBox(height: 6),
                const SkeletonBox(width: 50, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.avg, required this.count});
  final double avg;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 13, color: MoproTokens.ratingStar),
        const SizedBox(width: 2),
        Text(
          avg.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '($count)',
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
