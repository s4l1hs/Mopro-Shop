import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mopro/features/catalog/widgets/cashback_chip.dart';
import 'package:mopro/utils/money.dart';
import 'package:mopro_api/mopro_api.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    required this.product,
    required this.onTap,
    super.key,
  });

  final ProductSummary product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final priceStr = MoneyUtils.formatMinor(product.priceMinor);

    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Hero(
                tag: 'product-image-${product.id}',
                child: product.coverImageUrl != null &&
                        product.coverImageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: product.coverImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, __, ___) => _PlaceholderImage(
                          colorScheme: colorScheme,
                        ),
                      )
                    : _PlaceholderImage(colorScheme: colorScheme),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    priceStr,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
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

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) => Container(
        color: colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.image_outlined,
          size: 40,
          color: colorScheme.outlineVariant,
        ),
      );
}
