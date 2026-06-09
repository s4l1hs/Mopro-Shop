import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro_api/mopro_api.dart';

class SearchState {
  const SearchState({
    this.query = '',
    this.results = const AsyncData([]),
    this.loadingMore = false,
    this.loadMoreError,
    this.hasMore = false,
    this.page = 1,
  });

  final String query;
  final AsyncValue<List<ProductSummary>> results;
  final bool loadingMore;
  final AppError? loadMoreError;
  final bool hasMore;
  final int page;

  bool get isEmpty => query.isEmpty;

  SearchState copyWith({
    String? query,
    AsyncValue<List<ProductSummary>>? results,
    bool? loadingMore,
    AppError? loadMoreError,
    bool clearLoadMoreError = false,
    bool? hasMore,
    int? page,
  }) =>
      SearchState(
        query: query ?? this.query,
        results: results ?? this.results,
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError:
            clearLoadMoreError ? null : loadMoreError ?? this.loadMoreError,
        hasMore: hasMore ?? this.hasMore,
        page: page ?? this.page,
      );
}

final searchProvider =
    NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);

class SearchNotifier extends Notifier<SearchState> {
  Timer? _debounce;

  @override
  SearchState build() => const SearchState();

  void setQuery(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    if (trimmed == state.query) return;
    if (trimmed.isEmpty) {
      state = const SearchState();
      return;
    }
    state = state.copyWith(
      query: trimmed,
      results: const AsyncLoading(),
      page: 1,
      hasMore: false,
    );
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(1));
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore || state.query.isEmpty) return;
    state = state.copyWith(loadingMore: true, clearLoadMoreError: true);
    await _load(state.page + 1);
  }

  /// Re-runs the search from page 1 with the current filter state for the active
  /// query. SearchScreen calls this when `plpFiltersProvider(plpKeyForSearch(query))`
  /// changes — this singleton provider doesn't watch the query-keyed filter, so
  /// the screen drives the refetch.
  void reapplyFilters() {
    if (state.query.isEmpty) return;
    state = state.copyWith(
      results: const AsyncLoading(),
      page: 1,
      hasMore: false,
    );
    _load(1);
  }

  Future<void> _load(int page) async {
    final query = state.query;
    if (query.isEmpty) return;
    try {
      final api = ref.read(searchApiProvider);
      final f = ref.read(plpFiltersProvider(plpKeyForSearch(query)));
      final resp = await api.search(
        q: query,
        page: page,
        sort: f.sort.token,
        minPrice: f.priceMinMinor,
        maxPrice: f.priceMaxMinor,
        brand: f.brands.isEmpty ? null : f.brands,
        rating: f.ratingMin,
        freeShipping: f.freeShippingOnly ? true : null,
        inStock: f.inStock ? true : null,
        priceDropped: f.priceDropped ? true : null,
      );
      final incoming = resp.data?.data ?? [];
      final meta = resp.data?.pagination;
      final existing =
          page == 1 ? <ProductSummary>[] : state.results.valueOrNull ?? [];
      state = state.copyWith(
        results: AsyncData([...existing, ...incoming]),
        loadingMore: false,
        hasMore: meta != null && page < meta.totalPages,
        page: page,
        clearLoadMoreError: true,
      );
    } on DioException catch (e, st) {
      final err = e.error;
      final appError =
          err is AppError ? err : NetworkError(message: e.message ?? '');
      if (page == 1) {
        state = state.copyWith(results: AsyncError(appError, st));
      } else {
        state = state.copyWith(loadMoreError: appError, loadingMore: false);
      }
    } catch (e, st) {
      final appError = UnknownError(statusCode: 0, message: e.toString());
      if (page == 1) {
        state = state.copyWith(results: AsyncError(appError, st));
      } else {
        state = state.copyWith(loadMoreError: appError, loadingMore: false);
      }
    }
  }
}
