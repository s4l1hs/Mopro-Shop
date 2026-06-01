import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';

const int kSellerReturnsPageSize = 20;

class SellerReturnsState {
  const SellerReturnsState({
    this.items = const [],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  });

  final List<SellerReturn> items;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  SellerReturnsState copyWith({
    List<SellerReturn>? items,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) =>
      SellerReturnsState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Seller returns inbox, keyed by status filter ('submitted'|'approved'|
/// 'rejected'; '' = all). Shape #1.
class SellerReturnsNotifier extends FamilyNotifier<SellerReturnsState, String> {
  late String _status;

  @override
  SellerReturnsState build(String status) {
    _status = status;
    Future<void>.microtask(refresh);
    return const SellerReturnsState();
  }

  SellerRepository get _repo => ref.read(sellerRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final (items, hasMore) =
          await _repo.listReturns(status: _status);
      state = SellerReturnsState(items: items, loading: false, hasMore: hasMore);
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final (items, hasMore) = await _repo.listReturns(
        status: _status,
        offset: state.items.length,
      );
      state = state.copyWith(
        items: [...state.items, ...items],
        hasMore: hasMore,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

final sellerReturnsInboxProvider =
    NotifierProvider.family<SellerReturnsNotifier, SellerReturnsState, String>(
  SellerReturnsNotifier.new,
);

/// Finds a single return by id (deep-link to detail without `extra`). Fetches a
/// wide page across all statuses and matches. Seed-scale; pagination beyond the
/// first 100 is Backlog.
final sellerReturnByIdProvider =
    FutureProvider.family.autoDispose<SellerReturn?, int>((ref, id) async {
  final (items, _) =
      await ref.watch(sellerRepositoryProvider).listReturns(status: '', limit: 100);
  for (final r in items) {
    if (r.id == id) return r;
  }
  return null;
});
