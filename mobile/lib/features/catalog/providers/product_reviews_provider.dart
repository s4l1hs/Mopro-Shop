import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';

class ProductReview {
  const ProductReview({
    required this.id,
    required this.userId,
    required this.rating,
    required this.title,
    required this.body,
    required this.helpfulCount,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final int rating;
  final String title;
  final String body;
  final int helpfulCount;
  final String createdAt;

  factory ProductReview.fromJson(Map<String, dynamic> j) => ProductReview(
        id: j['id'] as int,
        userId: j['user_id'] as int,
        rating: j['rating'] as int,
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        helpfulCount: (j['helpful_count'] as int?) ?? 0,
        createdAt: (j['created_at'] as String?) ?? '',
      );
}

/// Fetches GET /products/{id}/reviews — public endpoint, pagination naive
/// (first page only for now; load-more deferred until UX needs it).
final productReviewsProvider =
    FutureProvider.autoDispose.family<List<ProductReview>, int>(
  (ref, productId) async {
    final dio = ref.watch(dioProvider);
    try {
      final resp = await dio.get<Map<String, dynamic>>(
        '/products/$productId/reviews',
        queryParameters: <String, dynamic>{'page': 1, 'per_page': 20},
      );
      final data = (resp.data?['data'] as List<dynamic>?) ?? [];
      return data
          .map((e) => ProductReview.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException {
      return const [];
    }
  },
);
