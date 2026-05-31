import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';

/// Thrown by [ReviewWriteRepository.create] on the 409 the backend returns when
/// a (product, user) review already exists. Carries the existing review id so
/// the UI can pivot the user into edit mode.
class ReviewAlreadyExists implements Exception {
  const ReviewAlreadyExists(this.existingReviewId);
  final int existingReviewId;
}

/// One of the current user's own reviews, enriched with product display info
/// (snake_case wire shape from GET /me/reviews → `data[]`).
class UserReview {
  const UserReview({
    required this.id,
    required this.productId,
    required this.rating,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.productTitle,
    required this.productSlug,
    required this.productThumbnail,
  });

  factory UserReview.fromJson(Map<String, dynamic> j) => UserReview(
        id: (j['id'] as num).toInt(),
        productId: (j['product_id'] as num?)?.toInt() ?? 0,
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        status: (j['status'] as String?) ?? '',
        createdAt: DateTime.tryParse((j['created_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse((j['updated_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        productTitle: (j['product_title'] as String?) ?? '',
        productSlug: (j['product_slug'] as String?) ?? '',
        productThumbnail: (j['product_thumbnail'] as String?) ?? '',
      );

  final int id;
  final int productId;
  final int rating;
  final String title;
  final String body;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String productTitle;
  final String productSlug;
  final String productThumbnail;
}

/// Server-computed review block for a (user, product): whether the user may
/// leave a review, until when, and the id of any existing review.
class ReviewEligibility {
  const ReviewEligibility({
    required this.canReview,
    this.reviewableUntil,
    this.existingReviewId = 0,
  });

  factory ReviewEligibility.fromJson(Map<String, dynamic> j) =>
      ReviewEligibility(
        canReview: (j['canReview'] as bool?) ?? false,
        reviewableUntil: DateTime.tryParse(
          (j['reviewableUntil'] as String?) ?? '',
        ),
        existingReviewId: (j['existingReviewId'] as num?)?.toInt() ?? 0,
      );

  final bool canReview;
  final DateTime? reviewableUntil;
  final int existingReviewId;

  bool get hasExisting => existingReviewId > 0;
}

/// Thin wrapper over the reviews write endpoints. All calls assume the caller is
/// authenticated (the UI gates guests via the adaptive login presenter).
class ReviewWriteRepository {
  ReviewWriteRepository(this._dio);

  final Dio _dio;

  /// POST /products/{id}/reviews. Throws [ReviewAlreadyExists] on a 409.
  Future<void> create(
    int productId, {
    required int rating,
    required String title,
    required String body,
    required String locale,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/products/$productId/reviews',
        data: <String, dynamic>{
          'rating': rating,
          'title': title,
          'body': body,
          'submittedLocale': locale,
        },
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final data = e.response?.data;
        final existing = data is Map<String, dynamic>
            ? (data['existingReviewId'] as num?)?.toInt() ?? 0
            : 0;
        throw ReviewAlreadyExists(existing);
      }
      rethrow;
    }
  }

  /// PUT /products/{productId}/reviews/{reviewId}.
  Future<void> update(
    int productId,
    int reviewId, {
    required int rating,
    required String title,
    required String body,
    required String locale,
  }) async {
    await _dio.put<Map<String, dynamic>>(
      '/products/$productId/reviews/$reviewId',
      data: <String, dynamic>{
        'rating': rating,
        'title': title,
        'body': body,
        'submittedLocale': locale,
      },
    );
  }

  /// DELETE /products/{productId}/reviews/{reviewId} (soft delete server-side).
  Future<void> delete(int productId, int reviewId) async {
    await _dio.delete<void>('/products/$productId/reviews/$reviewId');
  }

  /// GET /me/reviews → (items, total, hasMore).
  Future<(List<UserReview>, int, bool)> listMine({
    required int page,
    required int pageSize,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/me/reviews',
      queryParameters: <String, dynamic>{'page': page, 'pageSize': pageSize},
    );
    final data = resp.data ?? const {};
    final items = ((data['data'] as List<dynamic>?) ?? const [])
        .map((e) => UserReview.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = (data['total'] as num?)?.toInt() ?? items.length;
    final hasMore = (data['hasMore'] as bool?) ?? false;
    return (items, total, hasMore);
  }

  /// GET /products/{id}/review-eligibility.
  Future<ReviewEligibility> eligibility(int productId) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/products/$productId/review-eligibility',
    );
    final data = resp.data ?? const {};
    return ReviewEligibility.fromJson(
      (data['eligibility'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

final reviewWriteRepositoryProvider = Provider<ReviewWriteRepository>(
  (ref) => ReviewWriteRepository(ref.watch(dioProvider)),
);

/// The current user's review eligibility for a productId. Auto-disposed; the
/// PDP refreshes it after a successful submit by invalidating this provider.
final reviewEligibilityProvider =
    FutureProvider.family.autoDispose<ReviewEligibility, int>((ref, productId) {
  return ref.watch(reviewWriteRepositoryProvider).eligibility(productId);
});

/// Paginated list state for the current user's reviews (`/account/reviews`).
class MyReviewsState {
  const MyReviewsState({
    this.items = const [],
    this.total = 0,
    this.page = 0,
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  });

  final List<UserReview> items;
  final int total;
  final int page;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final Object? error;

  MyReviewsState copyWith({
    List<UserReview>? items,
    int? total,
    int? page,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    Object? error,
    bool clearError = false,
  }) =>
      MyReviewsState(
        items: items ?? this.items,
        total: total ?? this.total,
        page: page ?? this.page,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

const int kMyReviewsPageSize = 20;

/// Notifier for `/account/reviews`. Follows shape #1: explicit immutable state,
/// optimistic delete with rollback, append-style pagination.
class MyReviewsNotifier extends Notifier<MyReviewsState> {
  @override
  MyReviewsState build() {
    Future<void>.microtask(refresh);
    return const MyReviewsState();
  }

  ReviewWriteRepository get _repo => ref.read(reviewWriteRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final (items, total, hasMore) =
          await _repo.listMine(page: 1, pageSize: kMyReviewsPageSize);
      state = MyReviewsState(
        items: items,
        total: total,
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
      final (items, total, hasMore) = await _repo.listMine(
        page: state.page + 1,
        pageSize: kMyReviewsPageSize,
      );
      state = state.copyWith(
        items: [...state.items, ...items],
        total: total,
        page: state.page + 1,
        hasMore: hasMore,
        loadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }

  /// Optimistically removes [reviewId]; rolls back and returns false on failure.
  Future<bool> delete(int productId, int reviewId) async {
    final original = state.items;
    final idx = original.indexWhere((r) => r.id == reviewId);
    if (idx < 0) return false;
    state = state.copyWith(
      items: [...original]..removeAt(idx),
      total: state.total > 0 ? state.total - 1 : 0,
    );
    try {
      await _repo.delete(productId, reviewId);
      return true;
    } catch (_) {
      state = state.copyWith(items: original, total: state.total + 1);
      return false;
    }
  }
}

final myReviewsProvider =
    NotifierProvider<MyReviewsNotifier, MyReviewsState>(MyReviewsNotifier.new);
