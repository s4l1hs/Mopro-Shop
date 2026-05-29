import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/providers/products_by_category_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// Family key is the category id as a string (e.g. `'42'`). The active sort is
/// sourced from `plpFiltersProvider(categoryId)`; changing the sort rebuilds
/// this provider and refetches from page 1. (Price/brand/rating/shipping live
/// in the same filter state for the URL + the 5b sidebar but do not yet affect
/// the fetch — the catalog API only filters by sort today; see REPORT §8.4.)
final filteredProductsProvider =
    NotifierProviderFamily<FilteredProductsNotifier, ProductsState, String>(
  FilteredProductsNotifier.new,
);

class FilteredProductsNotifier
    extends FamilyNotifier<ProductsState, String> {
  late int _categoryId;
  late String _sort;

  @override
  ProductsState build(String arg) {
    _categoryId = int.parse(arg);
    _sort = ref.watch(plpFiltersProvider(arg).select((f) => f.sort)).token;
    _load(1, replace: true);
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
      final resp = await api.listProducts(
        categoryId: _categoryId,
        page: page,
        sort: _sort,
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
