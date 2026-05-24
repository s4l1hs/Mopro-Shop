import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/error_banner.dart';
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
  String _sort = 'recommended';
  ProductFilterOptions _filterOpts = const ProductFilterOptions();

  ProductFilter get _filter =>
      ProductFilter(categoryId: widget.categoryId, sort: _sort);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(filteredProductsProvider(_filter));
    final products = state.products.valueOrNull ?? [];
    final isLoading = state.products.isLoading;
    final hasError =
        state.products.hasError && products.isEmpty && !isLoading;

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
                ref.read(filteredProductsProvider(_filter).notifier).refresh(),
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
            ref.read(filteredProductsProvider(_filter).notifier).loadMore(),
        currentSort: _sort,
        onSort: _showSortSheet,
        onFilter: _showFilterSheet,
        activeFilterCount: _filterOpts.activeCount,
        onRefresh: () async =>
            ref.read(filteredProductsProvider(_filter).notifier).refresh(),
      ),
    );
  }

  Future<void> _showSortSheet() async {
    final selected = await showSortSheet(context, current: _sort);
    if (selected != null && selected != _sort) {
      setState(() => _sort = selected);
    }
  }

  Future<void> _showFilterSheet() async {
    final result = await showFilterSheet(context, current: _filterOpts);
    if (result != null) {
      setState(() => _filterOpts = result);
    }
  }
}
