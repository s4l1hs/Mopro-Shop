import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/empty_state.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/catalog/providers/search_provider.dart';
import 'package:mopro/features/catalog/widgets/product_grid.dart';
import 'package:mopro/features/catalog/widgets/search_input.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);

    return Scaffold(
      appBar: AppBar(
        title: SearchInput(
          onChanged: ref.read(searchProvider.notifier).setQuery,
          autofocus: true,
        ),
        titleSpacing: 0,
      ),
      body: state.isEmpty
          ? EmptyState.empty()
          : state.results.when(
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
                    onRetry: () => ref
                        .read(searchProvider.notifier)
                        .setQuery(state.query),
                  ),
                );
              },
              data: (results) {
                if (results.isEmpty) {
                  return EmptyState.notFound();
                }
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(12),
                      sliver: ProductGrid(
                        products: results,
                        onProductTap: (p) =>
                            context.push('/products/${p.id}'),
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
                                        .read(searchProvider.notifier)
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
                            onRetry: () =>
                                ref
                                    .read(searchProvider.notifier)
                                    .loadMore(),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(
                        child: SizedBox(height: 24)),
                  ],
                );
              },
            ),
    );
  }
}
