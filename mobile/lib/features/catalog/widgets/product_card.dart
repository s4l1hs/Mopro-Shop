import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/design/widgets/responsive_network_image.dart';
import 'package:mopro/features/catalog/widgets/cashback_chip.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
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
  });

  final ProductSummary product;
  final VoidCallback onTap;
  final int? originalPriceMinor;
  final int? discountPct;
  final double? ratingAvg;
  final int ratingCount;

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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935), // discount red
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '%$effectiveDiscountPct',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    priceStr,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: MoproTokens.primaryLight,
                    ),
                  ),
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
