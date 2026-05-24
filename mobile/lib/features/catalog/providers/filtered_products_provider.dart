import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/catalog/providers/products_by_category_provider.dart';
import 'package:mopro_api/mopro_api.dart';

@immutable
class ProductFilter {
  const ProductFilter({required this.categoryId, this.sort = 'recommended'});

  final int categoryId;
  final String sort;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductFilter &&
          categoryId == other.categoryId &&
          sort == other.sort);

  @override
  int get hashCode => Object.hash(categoryId, sort);
}

final filteredProductsProvider =
    NotifierProviderFamily<FilteredProductsNotifier, ProductsState, ProductFilter>(
  FilteredProductsNotifier.new,
);

class FilteredProductsNotifier
    extends FamilyNotifier<ProductsState, ProductFilter> {
  static const _perPage = 20;

  @override
  ProductsState build(ProductFilter arg) {
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
        categoryId: arg.categoryId,
        page: page,
        perPage: _perPage,
        sort: arg.sort,
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
