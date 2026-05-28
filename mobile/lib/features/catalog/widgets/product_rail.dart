import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';

class ProductRail extends ConsumerWidget {
  const ProductRail({
    required this.title,
    required this.sort,
    this.seeAllRoute,
    super.key,
  });

  final String title;
  final String sort;
  final String? seeAllRoute;

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
        SizedBox(
          height: 258,
          child: async.when(
            loading: _SkeletonRail.new,
            error: (_, __) => const SizedBox.shrink(),
            data: (products) {
              if (products.isEmpty) return const SizedBox.shrink();
              return ListView.separated(
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
                      onTap: () => context.push('/products/${p.id}'),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SkeletonRail extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, __) => const SizedBox(
        width: 152,
        child: SkeletonProductCard(),
      ),
    );
  }
}
