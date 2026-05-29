import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/utils/debouncer.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_codec.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/providers/filtered_products_provider.dart';
import 'package:mopro/features/catalog/widgets/filter_sheet.dart';
import 'package:mopro/features/catalog/widgets/sort_sheet.dart';
import 'package:mopro/widgets/catalog/catalog_shell.dart';

class CategoryProductsScreen extends ConsumerStatefulWidget {
  const CategoryProductsScreen({
    required this.categoryId,
    required this.categoryName,
    super.key,
  });

  final int categoryId;
  final String categoryName;

  @override
  ConsumerState<CategoryProductsScreen> createState() =>
      _CategoryProductsScreenState();
}

class _CategoryProductsScreenState
    extends ConsumerState<CategoryProductsScreen> {
  static const _codec = PlpFiltersCodec();
  final _debouncer = Debouncer();
  bool _hydrated = false;

  String get _key => plpKeyForCategory(widget.categoryId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) return;
    _hydrated = true;
    // Hydrate filter state from the URL on entry (shareable/deep-linkable).
    final params = GoRouterState.of(context).uri.queryParameters;
    final decoded = _codec.decode(params);
    if (decoded != ref.read(plpFiltersProvider(_key))) {
      ref.read(plpFiltersProvider(_key).notifier).set(decoded);
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  void _writeUrl(PlpFilters next) {
    _debouncer.run(() {
      if (!mounted) return;
      final q = _codec.encode(next);
      final uri = GoRouterState.of(context)
          .uri
          .replace(queryParameters: q.isEmpty ? null : q);
      context.go(uri.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reflect PLP context in the browser tab title.
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(label: 'Mopro · ${widget.categoryName}'),
    );

    final filters = ref.watch(plpFiltersProvider(_key));
    // Mirror filter changes into the URL (debounced) from any source.
    ref.listen<PlpFilters>(plpFiltersProvider(_key), (_, next) => _writeUrl(next));

    final state = ref.watch(filteredProductsProvider(_key));
    final products = state.products.valueOrNull ?? [];
    final isLoading = state.products.isLoading;
    final hasError = state.products.hasError && products.isEmpty && !isLoading;

    if (hasError) {
      final err = state.products.error;
      final appError = err is AppError
          ? err
          : UnknownError(statusCode: 0, message: err.toString());
      return Scaffold(
        appBar: AppBar(title: Text(widget.categoryName)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorBanner(
            error: appError,
            onRetry: () =>
                ref.read(filteredProductsProvider(_key).notifier).refresh(),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
      body: CatalogShell(
        products: products,
        isLoading: isLoading,
        hasMore: state.hasMore,
        loadingMore: state.loadingMore,
        loadMoreError: state.loadMoreError,
        onLoadMore: () =>
            ref.read(filteredProductsProvider(_key).notifier).loadMore(),
        currentSort: filters.sort.token,
        onSort: _showSortSheet,
        onFilter: _showFilterSheet,
        activeFilterCount: filters.activeChipCount,
        onRefresh: () async =>
            ref.read(filteredProductsProvider(_key).notifier).refresh(),
      ),
    );
  }

  Future<void> _showSortSheet() async {
    final filters = ref.read(plpFiltersProvider(_key));
    final selected = await showSortSheet(context, current: filters.sort.token);
    if (selected != null) {
      ref
          .read(plpFiltersProvider(_key).notifier)
          .setSort(PlpSort.fromToken(selected));
    }
  }

  Future<void> _showFilterSheet() async {
    final filters = ref.read(plpFiltersProvider(_key));
    final current = ProductFilterOptions(
      minPriceMinor: filters.priceMinMinor,
      maxPriceMinor: filters.priceMaxMinor,
      freeShippingOnly: filters.freeShippingOnly,
    );
    final result = await showFilterSheet(context, current: current);
    if (result != null) {
      ref.read(plpFiltersProvider(_key).notifier).update(
            (f) => f.copyWith(
              priceMinMinor: result.minPriceMinor,
              priceMaxMinor: result.maxPriceMinor,
              freeShippingOnly: result.freeShippingOnly,
              page: 1,
            ),
          );
    }
  }
}
