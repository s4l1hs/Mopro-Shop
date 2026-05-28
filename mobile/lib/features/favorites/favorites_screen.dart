import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// Batch-fetches full product data via POST /products/batch.
/// Works for both guest (local IDs) and authed users.
final _favProductsProvider =
    FutureProvider.autoDispose<List<ProductSummary>>((ref) async {
  final ids = ref.watch(favoritesProvider);
  if (ids.isEmpty) return const [];

  final dio = ref.watch(dioProvider);
  try {
    final resp = await dio.post<Map<String, dynamic>>(
      '/products/batch',
      data: {'ids': ids.toList()},
    );
    final data = (resp.data?['data'] as List<dynamic>?) ?? [];
    return data
        .map((e) => ProductSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  } on DioException {
    return const [];
  } catch (_) {
    return const [];
  }
});

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(favoritesProvider);
    final productsAsync = ref.watch(_favProductsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('nav.favorites'.tr()),
        actions: [
          if (ids.isNotEmpty)
            TextButton(
              onPressed: () {
                for (final id in ids.toList()) {
                  ref.read(favoritesProvider.notifier).toggle(id);
                }
              },
              child: const Text('Temizle'),
            ),
        ],
      ),
      body: ids.isEmpty
          ? const _EmptyState()
          : productsAsync.when(
              loading: () => const _SkeletonGrid(),
              error: (_, __) => const _SkeletonGrid(),
              data: (products) => products.isEmpty
                  ? const _SkeletonGrid()
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(_favProductsProvider),
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.62,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: products.length,
                        itemBuilder: (ctx, i) {
                          final p = products[i];
                          return ProductCard(
                            product: p,
                            onTap: () => ctx.push('/products/${p.id}'),
                          );
                        },
                      ),
                    ),
            ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.62,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => const SkeletonProductCard(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.favorite_border_rounded,
              size: 40,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'favorites.empty_title'.tr(),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'favorites.empty_subtitle'.tr(),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text('Keşfet'),
          ),
        ],
      ),
    );
  }
}
