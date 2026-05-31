import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/seller/data/seller_storefront_repository.dart';
import 'package:mopro_api/mopro_api.dart';

/// The seller profile header, keyed by slug. Auto-disposed.
final sellerProfileProvider =
    FutureProvider.family.autoDispose<SellerProfile, String>((ref, slug) {
  return ref.watch(sellerStorefrontRepositoryProvider).getProfile(slug);
});

/// Paginated list state shared by the products + reviews tabs.
class SellerListState<T> {
  const SellerListState({
    this.items = const [],
    this.page = 0,
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  });

  final List<T> items;
  final int page;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  SellerListState<T> copyWith({
    List<T>? items,
    int? page,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) =>
      SellerListState<T>(
        items: items ?? this.items,
        page: page ?? this.page,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

const int kSellerReviewsPageSize = 20;

// ── Products tab ──────────────────────────────────────────────────────────────

class SellerProductsNotifier
    extends FamilyNotifier<SellerListState<ProductSummary>, String> {
  late String _slug;

  @override
  SellerListState<ProductSummary> build(String slug) {
    _slug = slug;
    Future<void>.microtask(refresh);
    return const SellerListState();
  }

  SellerStorefrontRepository get _repo =>
      ref.read(sellerStorefrontRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final (items, hasMore) = await _repo.listProducts(_slug, page: 1);
      state = SellerListState<ProductSummary>(
        items: items,
        page: 1,
        loading: false,
        hasMore: hasMore,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final (items, hasMore) =
          await _repo.listProducts(_slug, page: state.page + 1);
      state = state.copyWith(
        items: [...state.items, ...items],
        page: state.page + 1,
        hasMore: hasMore,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

final sellerProductsProvider = NotifierProvider.family<SellerProductsNotifier,
    SellerListState<ProductSummary>, String>(SellerProductsNotifier.new);

// ── Reviews tab ───────────────────────────────────────────────────────────────

class SellerReviewsNotifier
    extends FamilyNotifier<SellerListState<SellerReview>, String> {
  late String _slug;

  @override
  SellerListState<SellerReview> build(String slug) {
    _slug = slug;
    Future<void>.microtask(refresh);
    return const SellerListState();
  }

  SellerStorefrontRepository get _repo =>
      ref.read(sellerStorefrontRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final (items, hasMore) =
          await _repo.listReviews(_slug, page: 1, pageSize: kSellerReviewsPageSize);
      state = SellerListState<SellerReview>(
        items: items,
        page: 1,
        loading: false,
        hasMore: hasMore,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final (items, hasMore) = await _repo.listReviews(
        _slug,
        page: state.page + 1,
        pageSize: kSellerReviewsPageSize,
      );
      state = state.copyWith(
        items: [...state.items, ...items],
        page: state.page + 1,
        hasMore: hasMore,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

final sellerReviewsProvider = NotifierProvider.family<SellerReviewsNotifier,
    SellerListState<SellerReview>, String>(SellerReviewsNotifier.new);
