import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';

/// How many reviews are fetched per page (matches the backend default/cap).
const int kReviewsPageSize = 10;

/// Sort orders offered by the reviews list endpoint. [api] is the wire value.
enum ReviewSort {
  newest('newest'),
  highest('highest'),
  lowest('lowest'),
  helpful('helpful');

  const ReviewSort(this.api);
  final String api;
}

/// A single product review (camelCase wire shape from GET /products/{id}/reviews).
class Review {
  const Review({
    required this.id,
    required this.userId,
    required this.rating,
    required this.title,
    required this.body,
    required this.helpfulCount,
    required this.votedByCurrentUser,
    required this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: (j['id'] as num).toInt(),
        userId: (j['userId'] as num?)?.toInt() ?? 0,
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        helpfulCount: (j['helpfulCount'] as num?)?.toInt() ?? 0,
        votedByCurrentUser: (j['votedByCurrentUser'] as bool?) ?? false,
        createdAt: (j['createdAt'] as String?) ?? '',
      );

  final int id;
  final int userId;
  final int rating;
  final String title;
  final String body;
  final int helpfulCount;
  final bool votedByCurrentUser;
  final String createdAt;

  Review copyWith({int? helpfulCount, bool? votedByCurrentUser}) => Review(
        id: id,
        userId: userId,
        rating: rating,
        title: title,
        body: body,
        helpfulCount: helpfulCount ?? this.helpfulCount,
        votedByCurrentUser: votedByCurrentUser ?? this.votedByCurrentUser,
        createdAt: createdAt,
      );
}

/// Product-level rating aggregate driving the histogram. Identical across pages.
class ReviewsSummary {
  const ReviewsSummary({
    required this.average,
    required this.distribution,
    required this.totalCount,
  });

  factory ReviewsSummary.fromJson(Map<String, dynamic> j) {
    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    final raw = (j['distribution'] as Map<String, dynamic>?) ?? const {};
    for (final entry in raw.entries) {
      final star = int.tryParse(entry.key);
      if (star != null) dist[star] = (entry.value as num?)?.toInt() ?? 0;
    }
    return ReviewsSummary(
      average: (j['average'] as num?)?.toDouble() ?? 0.0,
      distribution: dist,
      totalCount: (j['totalCount'] as num?)?.toInt() ?? 0,
    );
  }

  final double average;
  final Map<int, int> distribution;
  final int totalCount;
}

/// Immutable reviews-tab state. Follows shape #1 from CONTRIBUTING.md.
class ReviewsState {
  const ReviewsState({
    this.items = const [],
    this.total = 0,
    this.page = 0,
    this.sort = ReviewSort.newest,
    this.summary,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  });

  final List<Review> items;
  final int total;
  final int page;
  final ReviewSort sort;
  final ReviewsSummary? summary;
  final bool loading; // initial fetch / sort change
  final bool loadingMore; // pagination
  final Object? error;

  /// True when more pages remain to load.
  bool get hasMore => items.length < total;

  ReviewsState copyWith({
    List<Review>? items,
    int? total,
    int? page,
    ReviewSort? sort,
    ReviewsSummary? summary,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) =>
      ReviewsState(
        items: items ?? this.items,
        total: total ?? this.total,
        page: page ?? this.page,
        sort: sort ?? this.sort,
        summary: summary ?? this.summary,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Reviews notifier, keyed by productId. Not an AsyncNotifier because pagination
/// state needs explicit handling and the helpful toggle is optimistic.
class ReviewsNotifier extends FamilyNotifier<ReviewsState, int> {
  // Not `late final`: the family Notifier rebuilds when invalidated (e.g. after
  // a review submit), re-running build() and reassigning this.
  late int _productId;

  @override
  ReviewsState build(int productId) {
    _productId = productId;
    Future<void>.microtask(_loadInitial);
    return const ReviewsState();
  }

  Dio get _dio => ref.read(dioProvider);

  Future<void> _loadInitial() => _fetchFirstPage(state.sort);

  Future<void> _fetchFirstPage(ReviewSort sort) async {
    state = state.copyWith(loading: true, sort: sort, clearError: true);
    try {
      final (items, total, summary) = await _fetchPage(sort, 1);
      state = state.copyWith(
        items: items,
        total: total,
        page: 1,
        summary: summary,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    }
  }

  /// Re-fetches from page 1 with the new sort.
  Future<void> setSort(ReviewSort sort) async {
    if (sort == state.sort && !state.loading && state.error == null) return;
    await _fetchFirstPage(sort);
  }

  /// Appends the next page to the existing list.
  Future<void> loadMore() async {
    if (state.loadingMore || state.loading || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final (items, total, _) = await _fetchPage(state.sort, state.page + 1);
      state = state.copyWith(
        items: [...state.items, ...items],
        total: total,
        page: state.page + 1,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }

  /// Optimistically toggles the helpful vote for [reviewId]. Assumes the caller
  /// is authenticated (the UI gates guests via requireAuth). Returns true on
  /// success; on failure it rolls back to the pre-tap state and returns false so
  /// the caller can surface a SnackBar.
  Future<bool> toggleHelpful(int reviewId) async {
    final idx = state.items.indexWhere((r) => r.id == reviewId);
    if (idx < 0) return false;
    final original = state.items[idx];

    // 1–3. Optimistic flip.
    final optimistic = original.copyWith(
      votedByCurrentUser: !original.votedByCurrentUser,
      helpfulCount:
          original.helpfulCount + (original.votedByCurrentUser ? -1 : 1),
    );
    state = state.copyWith(items: _replace(state.items, idx, optimistic));

    try {
      // 4. Fire the request.
      final resp = await _dio.post<Map<String, dynamic>>(
        '/products/$_productId/reviews/$reviewId/helpful',
      );
      final data = resp.data ?? const {};
      final voted = (data['voted'] as bool?) ?? optimistic.votedByCurrentUser;
      final count =
          (data['helpfulCount'] as num?)?.toInt() ?? optimistic.helpfulCount;
      // 5. Reconcile with the server-authoritative state (handles races).
      final cur = state.items.indexWhere((r) => r.id == reviewId);
      if (cur >= 0) {
        state = state.copyWith(
          items: _replace(
            state.items,
            cur,
            state.items[cur]
                .copyWith(votedByCurrentUser: voted, helpfulCount: count),
          ),
        );
      }
      return true;
    } catch (_) {
      // 6. Roll back to the original value.
      final cur = state.items.indexWhere((r) => r.id == reviewId);
      if (cur >= 0) {
        state = state.copyWith(items: _replace(state.items, cur, original));
      }
      return false;
    }
  }

  static List<Review> _replace(List<Review> list, int idx, Review v) {
    final copy = [...list];
    copy[idx] = v;
    return copy;
  }

  /// GET one page; returns (items, total, summary).
  Future<(List<Review>, int, ReviewsSummary)> _fetchPage(
    ReviewSort sort,
    int page,
  ) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/products/$_productId/reviews',
      queryParameters: <String, dynamic>{
        'sort': sort.api,
        'page': page,
        'pageSize': kReviewsPageSize,
      },
    );
    final data = resp.data ?? const {};
    final items = ((data['items'] as List<dynamic>?) ?? const [])
        .map((e) => Review.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (data['total'] as num?)?.toInt() ?? items.length;
    final summary = ReviewsSummary.fromJson(
      (data['summary'] as Map<String, dynamic>?) ?? const {},
    );
    return (items, total, summary);
  }
}

/// Reviews state keyed by productId.
final reviewsNotifierProvider =
    NotifierProvider.family<ReviewsNotifier, ReviewsState, int>(
  ReviewsNotifier.new,
);
