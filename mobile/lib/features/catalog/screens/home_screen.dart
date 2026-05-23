import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/empty_state.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/providers/products_by_category_provider.dart';
import 'package:mopro/features/catalog/widgets/category_chip.dart';
import 'package:mopro/features/catalog/widgets/product_grid.dart';
import 'package:mopro/features/catalog/widgets/search_input.dart';
import 'package:mopro/features/home/providers/home_wallet_summary_provider.dart';
import 'package:mopro/features/wallet/widgets/coin_balance_pill.dart';
import 'package:mopro_api/mopro_api.dart';

class CatalogHomeScreen extends ConsumerStatefulWidget {
  const CatalogHomeScreen({super.key});

  @override
  ConsumerState<CatalogHomeScreen> createState() =>
      _CatalogHomeScreenState();
}

class _CatalogHomeScreenState extends ConsumerState<CatalogHomeScreen> {
  Category? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final categoriesState = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('home.title'.tr()),
        actions: [
          _CoinBalanceAction(),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: categoriesState.categories.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (err, _) {
          final appError = err is AppError
              ? err
              : UnknownError(statusCode: 0, message: err.toString());
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () =>
                  ref.read(categoriesProvider.notifier).refresh(),
            ),
          );
        },
        data: (categories) {
          final selected = _selectedCategory ?? categories.firstOrNull;
          return _CategoryProductsView(
            categories: categories,
            selectedCategory: selected,
            onCategorySelected: (cat) =>
                setState(() => _selectedCategory = cat),
          );
        },
      ),
    );
  }
}

class _CategoryProductsView extends ConsumerWidget {
  const _CategoryProductsView({
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  final List<Category> categories;
  final Category? selectedCategory;
  final void Function(Category) onCategorySelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catId = selectedCategory?.id;
    final productsState =
        catId != null ? ref.watch(productsByCategoryProvider(catId)) : null;

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(categoriesProvider.notifier).refresh();
        if (catId != null) {
          await ref
              .read(productsByCategoryProvider(catId).notifier)
              .refresh();
        }
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => CategoryChip(
                  category: categories[i],
                  selected: selectedCategory?.id == categories[i].id,
                  onTap: () => onCategorySelected(categories[i]),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          if (productsState == null)
            SliverToBoxAdapter(
              child: EmptyState.empty(),
            )
          else ..._productSlivers(context, ref, productsState, catId!),
        ],
      ),
    );
  }

  List<Widget> _productSlivers(
    BuildContext context,
    WidgetRef ref,
    ProductsState state,
    int catId,
  ) {
    if (state.products.isLoading) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (state.products.hasError) {
      final err = state.products.error;
      final appError = err is AppError
          ? err
          : UnknownError(statusCode: 0, message: err.toString());
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: appError,
              onRetry: () => ref
                  .read(productsByCategoryProvider(catId).notifier)
                  .refresh(),
            ),
          ),
        ),
      ];
    }
    final products = state.products.valueOrNull ?? [];
    if (products.isEmpty) {
      return [SliverToBoxAdapter(child: EmptyState.empty())];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: ProductGrid(
          products: products,
          onProductTap: (p) => context.push('/products/${p.id}'),
        ),
      ),
      if (state.hasMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: state.loadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: () => ref
                          .read(productsByCategoryProvider(catId).notifier)
                          .loadMore(),
                      child: Text('catalog.load_more'.tr()),
                    ),
            ),
          ),
        ),
      if (state.loadMoreError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorBanner(
              error: state.loadMoreError!,
              onRetry: () => ref
                  .read(productsByCategoryProvider(catId).notifier)
                  .loadMore(),
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }
}

class _CoinBalanceAction extends ConsumerWidget {
  const _CoinBalanceAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(homeWalletSummaryProvider);
    return summaryAsync.maybeWhen(
      data: (balance) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: CoinBalancePill(
          amountMinor: balance.amountMinor,
          currency: balance.currency,
          onTap: () => context.push('/wallet'),
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}
