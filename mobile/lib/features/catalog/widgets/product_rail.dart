import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro_api/mopro_api.dart';

/// How a [ProductRail] lays out its products.
enum RailLayout {
  /// Horizontal scroller (mobile).
  scroller,

  /// Fixed-column grid clamped to [ProductRail.maxItems] (tablet/desktop).
  grid,
}

class ProductRail extends ConsumerWidget {
  const ProductRail({
    required this.title,
    required this.sort,
    this.seeAllRoute,
    this.layout = RailLayout.scroller,
    this.gridColumns = 3,
    this.maxItems,
    super.key,
  });

  final String title;
  final String sort;
  final String? seeAllRoute;

  /// Scroller (mobile) or grid (tablet/desktop). The parent picks by breakpoint.
  final RailLayout layout;

  /// Columns when [layout] is grid.
  final int gridColumns;

  /// Item cap when [layout] is grid (e.g. 6 on tablet, 10 on desktop).
  final int? maxItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(productsRailProvider(sort));

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
              if (seeAllRoute != null)
                TextButton(
                  onPressed: () => context.push(seeAllRoute!),
                  child: Text('home.see_all'.tr()),
                ),
            ],
          ),
        ),
        async.when(
          loading: () => layout == RailLayout.grid
              ? _SkeletonGrid(columns: gridColumns, count: maxItems ?? 6)
              : const _SkeletonRail(),
          error: (_, __) => const SizedBox.shrink(),
          data: (products) {
            if (products.isEmpty) return const SizedBox.shrink();
            if (layout == RailLayout.grid) {
              return _RailGrid(
                products: products,
                columns: gridColumns,
                maxItems: maxItems,
              );
            }
            return SizedBox(
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
                      basketDiscountPct: p.basketDiscountPct,
                      onTap: () => context.push('/products/${p.id}'),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _RailGrid extends StatelessWidget {
  const _RailGrid({
    required this.products,
    required this.columns,
    this.maxItems,
  });
  final List<ProductSummary> products;
  final int columns;
  final int? maxItems;

  @override
  Widget build(BuildContext context) {
    final cap = maxItems;
    final items = (cap != null && products.length > cap)
        ? products.sublist(0, cap)
        : products;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.62,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final p = items[i];
          return ProductCard(
            product: p,
            isBestseller: p.isBestseller ?? false,
            basketDiscountPct: p.basketDiscountPct,
            onTap: () => context.push('/products/${p.id}'),
          );
        },
      ),
    );
  }
}

class _SkeletonRail extends StatelessWidget {
  const _SkeletonRail();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 258,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, __) => const SizedBox(
          width: 152,
          child: SkeletonProductCard(),
        ),
      ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid({required this.columns, required this.count});
  final int columns;
  final int count;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.62,
        ),
        itemCount: count,
        itemBuilder: (_, __) => const SkeletonProductCard(),
      ),
    );
  }
}
