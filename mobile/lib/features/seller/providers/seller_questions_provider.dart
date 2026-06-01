import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';

const int kSellerQuestionsPageSize = 20;

class SellerQuestionsState {
  const SellerQuestionsState({
    this.items = const [],
    this.page = 0,
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  });

  final List<SellerQuestion> items;
  final int page;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  SellerQuestionsState copyWith({
    List<SellerQuestion>? items,
    int? page,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) =>
      SellerQuestionsState(
        items: items ?? this.items,
        page: page ?? this.page,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Seller Q&A inbox, keyed by the `unanswered` filter. Shape #1.
class SellerQuestionsNotifier
    extends FamilyNotifier<SellerQuestionsState, bool> {
  late bool _unanswered;

  @override
  SellerQuestionsState build(bool unanswered) {
    _unanswered = unanswered;
    Future<void>.microtask(refresh);
    return const SellerQuestionsState();
  }

  SellerRepository get _repo => ref.read(sellerRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final (items, _, hasMore) =
          await _repo.listQuestions(unanswered: _unanswered);
      state = SellerQuestionsState(
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
      final (items, _, hasMore) = await _repo.listQuestions(
        unanswered: _unanswered,
        page: state.page + 1,
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

final sellerQuestionsInboxProvider =
    NotifierProvider.family<SellerQuestionsNotifier, SellerQuestionsState, bool>(
  SellerQuestionsNotifier.new,
);

/// Finds a question by id for deep-link to detail without `extra` (the thread
/// needs the product id). Searches the "all" list. Seed-scale.
final sellerQuestionByIdProvider =
    FutureProvider.family.autoDispose<SellerQuestion?, int>((ref, id) async {
  final (items, _, _) = await ref
      .watch(sellerRepositoryProvider)
      .listQuestions(unanswered: false, pageSize: 100);
  for (final q in items) {
    if (q.id == id) return q;
  }
  return null;
});
