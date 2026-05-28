import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro_api/mopro_api.dart';

class ProductsState {
  const ProductsState({
    this.products = const AsyncLoading(),
    this.loadingMore = false,
    this.loadMoreError,
    this.hasMore = false,
    this.page = 1,
  });

  final AsyncValue<List<ProductSummary>> products;
  final bool loadingMore;
  final AppError? loadMoreError;
  final bool hasMore;
  final int page;

  ProductsState copyWith({
    AsyncValue<List<ProductSummary>>? products,
    bool? loadingMore,
    AppError? loadMoreError,
    bool clearLoadMoreError = false,
    bool? hasMore,
    int? page,
  }) =>
      ProductsState(
        products: products ?? this.products,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError:
            clearLoadMoreError ? null : loadMoreError ?? this.loadMoreError,
        hasMore: hasMore ?? this.hasMore,
        page: page ?? this.page,
      );
}

final productsByCategoryProvider = NotifierProviderFamily<
    ProductsByCategoryNotifier, ProductsState, int>(
  ProductsByCategoryNotifier.new,
);

class ProductsByCategoryNotifier
    extends FamilyNotifier<ProductsState, int> {
  static const _perPage = 20;

  @override
  ProductsState build(int arg) {
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
        categoryId: arg,
        page: page,
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
