import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// Favorites grid columns per breakpoint: 2 mobile / 4 tablet / 5 desktop.
int _favColumns(BuildContext context) =>
    context.isDesktop ? 5 : (context.isTablet ? 4 : 2);

/// Card + the FAV-05 add-to-cart button below it: slightly taller cell than
/// the bare ProductCard grids (0.62).
const double _favCellAspectRatio = 0.54;

/// Mobile keeps the full-width 12dp-padded grid (unchanged); tablet/desktop
/// center + clamp via [CenteredContentColumn].
Widget _wrapGrid(BuildContext context, Widget grid) =>
    context.isMobile ? grid : CenteredContentColumn(child: grid);

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

/// FAV-05: product IDs with an add-to-cart resolution in flight — disables the
/// card's button + shows its spinner while GET /products/{id} resolves.
final _atcBusyProvider = StateProvider.autoDispose<Set<int>>((_) => const {});

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
              child: Text('favorites.clear_all'.tr()),
            ),
        ],
      ),
      body: ids.isEmpty
          ? const _EmptyState()
          : productsAsync.when(
              loading: () => const _SkeletonGrid(),
              error: (_, __) => _ErrorState(
                onRetry: () => ref.invalidate(_favProductsProvider),
              ),
              data: (products) => products.isEmpty
                  ? const _SkeletonGrid()
                  : _PopulatedBody(products: products),
            ),
    );
  }
}

class _PopulatedBody extends ConsumerWidget {
  const _PopulatedBody({required this.products});

  final List<ProductSummary> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_favProductsProvider),
      child: _wrapGrid(
        context,
        GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _favColumns(context),
            childAspectRatio: _favCellAspectRatio,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: products.length,
          itemBuilder: (ctx, i) => _FavCard(product: products[i]),
        ),
      ),
    );
  }
}

/// FAV-05: the shared [ProductCard] + a favorites-local add-to-cart button.
/// The button stays out of the shared card (§3 — PLP/PDP lanes own surfaces
/// rendering it); variant resolution is client-side via GET /products/{id}.
class _FavCard extends ConsumerWidget {
  const _FavCard({required this.product});

  final ProductSummary product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(_atcBusyProvider).contains(product.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ProductCard(
            product: product,
            originalPriceMinor: product.originalPriceMinor,
            discountPct: product.discountPct,
            ratingAvg: product.ratingAvg,
            ratingCount: product.ratingCount ?? 0,
            isBestseller: product.isBestseller ?? false,
            isOfficialSeller: product.isOfficialSeller ?? false,
            basketDiscountPct: product.basketDiscountPct,
            onTap: () => context.push('/products/${product.id}'),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 32,
          child: OutlinedButton.icon(
            onPressed: busy ? null : () => _addToCart(context, ref),
            icon: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_shopping_cart_outlined, size: 16),
            label: Text(
              'product.add_to_cart'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  /// Resolves the product's variants (favorites store product IDs only):
  /// none in stock → OOS snackbar; exactly one in stock → direct add (the only
  /// purchasable choice); several in stock → the user must pick size/colour →
  /// PDP. Mirrors the PDP's add-to-cart snackbars.
  Future<void> _addToCart(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final busy = ref.read(_atcBusyProvider.notifier);
    busy.state = {...busy.state, product.id};
    try {
      final resp =
          await ref.read(catalogApiProvider).getProduct(id: product.id);
      final inStock = (resp.data?.variants ?? const <Variant>[])
          .where((v) => v.stock > 0)
          .toList();
      if (inStock.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text('favorites.out_of_stock'.tr())),
        );
        return;
      }
      if (inStock.length > 1) {
        messenger.showSnackBar(
          SnackBar(content: Text('favorites.select_options'.tr())),
        );
        if (context.mounted) {
          await context.push('/products/${product.id}');
        }
        return;
      }
      await ref.read(cartProvider.notifier).addItem(
            productId: product.id,
            variantId: inStock.first.id,
            qty: 1,
          );
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('cart.added_to_cart'.tr()),
            action: SnackBarAction(
              label: 'nav.cart'.tr(),
              onPressed: () => context.push('/cart'),
            ),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('cart.add_failed'.tr())),
      );
    } finally {
      busy.state = {...busy.state}..remove(product.id);
    }
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    final cols = _favColumns(context);
    return _wrapGrid(
      context,
      GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: _favCellAspectRatio,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: cols * 3,
        itemBuilder: (_, __) => const SkeletonProductCard(),
      ),
    );
  }
}

/// FAV-04: a real error state (message + retry) — replaces the old infinite
/// skeleton that a `/products/batch` failure used to fall through to.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'favorites.load_error'.tr(),
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('favorites.retry'.tr()),
          ),
        ],
      ),
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
            label: Text('favorites.explore'.tr()),
          ),
        ],
      ),
    );
  }
}
