import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/providers/products_by_category_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// Family key is the category id as a string (e.g. `'42'`). The full `PlpFilters`
/// (sort + price + brand + rating + free-shipping + in-stock) is sourced from
/// `plpFiltersProvider(categoryId)`; any filter/sort change rebuilds this provider
/// and refetches from page 1, passing every dimension to the P-028 filter-aware
/// catalog API. `loadMore` paginates with the same captured filter.
final filteredProductsProvider =
    NotifierProviderFamily<FilteredProductsNotifier, ProductsState, String>(
  FilteredProductsNotifier.new,
);

class FilteredProductsNotifier
    extends FamilyNotifier<ProductsState, String> {
  late int _categoryId;
  late PlpFilters _filters;

  @override
  ProductsState build(String arg) {
    _categoryId = int.parse(arg);
    _filters = ref.watch(plpFiltersProvider(arg));
    // Defer the fetch: _load mutates `state`, which is illegal during build
    // (the notifier isn't mounted yet). The microtask runs once build returns.
    Future.microtask(() => _load(1, replace: true));
    return const ProductsState();
  }

  Future<void> refresh() => _load(1, replace: true);

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearLoadMoreError: true);
    await _load(state.page + 1, replace: false);
  }

  Future<void> _load(int page, {required bool replace}) async {
    if (replace) {
      state = state.copyWith(products: const AsyncLoading(), page: 1);
    }
    try {
      final api = ref.read(catalogApiProvider);
      final f = _filters;
      final resp = await api.listProducts(
        categoryId: _categoryId,
        page: page,
        sort: f.sort.token,
        minPrice: f.priceMinMinor,
        maxPrice: f.priceMaxMinor,
        brand: f.brands.isEmpty ? null : f.brands,
        rating: f.ratingMin,
        freeShipping: f.freeShippingOnly ? true : null,
        inStock: f.inStock ? true : null,
      );
      final incoming = resp.data?.data ?? [];
      final meta = resp.data?.pagination;
      final existing =
          replace ? <ProductSummary>[] : state.products.valueOrNull ?? [];
      state = state.copyWith(
        products: AsyncData([...existing, ...incoming]),
        loadingMore: false,
        hasMore: meta != null && page < meta.totalPages,
        page: page,
        total: meta?.total,
        clearLoadMoreError: true,
      );
    } on DioException catch (e, st) {
      final err = e.error;
      final appError =
          err is AppError ? err : NetworkError(message: e.message ?? '');
      if (replace) {
        state = state.copyWith(products: AsyncError(appError, st));
      } else {
        state = state.copyWith(loadMoreError: appError, loadingMore: false);
      }
    } catch (e, st) {
      final appError = UnknownError(statusCode: 0, message: e.toString());
      if (replace) {
        state = state.copyWith(products: AsyncError(appError, st));
      } else {
        state = state.copyWith(loadMoreError: appError, loadingMore: false);
      }
    }
  }
}
