import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:mopro/widgets/cashback_chip.dart';
import 'package:mopro/widgets/price_display.dart';

class ProductCard extends ConsumerWidget {
  const ProductCard({
    required this.id,
    required this.title,
    required this.priceMinor,
    required this.onTap,
    this.imageUrl,
    this.commissionBps = 0,
    this.currency = 'TRY',
    super.key,
  });

  final int id;
  final String title;
  final int priceMinor;
  final String? imageUrl;
  final int commissionBps;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isFav = ref.watch(isFavoriteProvider(id));

    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: imageUrl != null && imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: cs.surfaceContainerHighest,
                          ),
                          errorWidget: (_, __, ___) =>
                              _Placeholder(cs: cs),
                        )
                      : _Placeholder(cs: cs),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: _FavButton(productId: id, isFav: isFav, ref: ref),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  PriceDisplay(
                    priceMinor: priceMinor,
                    currency: currency,
                    size: PriceDisplaySize.sm,
                  ),
                  const SizedBox(height: 4),
                  CashbackChip(
                    priceMinor: priceMinor,
                    commissionBps: commissionBps,
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

class _FavButton extends StatelessWidget {
  const _FavButton({
    required this.productId,
    required this.isFav,
    required this.ref,
  });

  final int productId;
  final bool isFav;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ref.read(favoritesProvider.notifier).toggle(productId),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(204),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isFav ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: isFav
              ? MoproTokens.destructiveLight
              : Colors.black54,
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(
          Icons.image_outlined,
          size: 40,
          color: cs.outlineVariant,
        ),
      );
}
