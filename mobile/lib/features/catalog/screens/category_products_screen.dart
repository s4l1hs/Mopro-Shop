import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/empty_state.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/catalog/providers/products_by_category_provider.dart';
import 'package:mopro/features/catalog/widgets/product_grid.dart';

class CategoryProductsScreen extends ConsumerWidget {
  const CategoryProductsScreen({
    required this.categoryId,
    required this.categoryName,
    super.key,
  });

  final int categoryId;
  final String categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(productsByCategoryProvider(categoryId));

    return Scaffold(
      appBar: AppBar(title: Text(categoryName)),
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(productsByCategoryProvider(categoryId).notifier)
            .refresh(),
        child: state.products.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) {
            final appError = err is AppError
                ? err
                : UnknownError(statusCode: 0, message: err.toString());
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorBanner(
                error: appError,
                onRetry: () => ref
                    .read(productsByCategoryProvider(categoryId).notifier)
                    .refresh(),
              ),
            );
          },
          data: (products) {
            if (products.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [EmptyState.empty()],
              );
            }
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(12),
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
                                    .read(productsByCategoryProvider(
                                            categoryId)
                                        .notifier)
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
                            .read(productsByCategoryProvider(categoryId)
                                .notifier)
                            .loadMore(),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        ),
      ),
    );
  }
}
