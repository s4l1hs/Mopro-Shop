import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro_api/mopro_api.dart';

/// A horizontal product rail rendered from a **client-supplied** list, as
/// opposed to `ProductRail` which fetches from a sort key. Same scroller visuals
/// (258dp tall, 152dp cards, 8dp gaps, 16dp padding) so it sits cleanly beside
/// the sort-key rails. Used by the "Son baktıkların" recently-viewed surface
/// (Tranche 4c). Renders nothing for an empty list.
class ProductListRail extends StatelessWidget {
  const ProductListRail({
    required this.products,
    required this.title,
    this.onSeeAll,
    super.key,
  });

  final List<ProductSummary> products;
  final String title;

  /// When non-null, a "Tümünü gör" link is shown at the end of the header row.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: Text('home.see_all'.tr()),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 258,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final p = products[i];
              return SizedBox(
                width: 152,
                child: ProductCard(
                  product: p,
                  isBestseller: p.isBestseller ?? false,
                  isOfficialSeller: p.isOfficialSeller ?? false,
                  basketDiscountPct: p.basketDiscountPct,
                  onTap: () => context.push('/products/${p.id}'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
