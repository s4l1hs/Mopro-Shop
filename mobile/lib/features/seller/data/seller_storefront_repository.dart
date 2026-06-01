import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro_api/mopro_api.dart';

/// A public seller storefront profile (GET /sellers/{slug}). The backend
/// resolves the locale-specific bio server-side, so this carries a single
/// already-resolved [bio] string.
class SellerProfile {
  const SellerProfile({
    required this.id,
    required this.slug,
    required this.displayName,
    required this.bio,
    required this.logoImageUrl,
    required this.bannerImageUrl,
    required this.ratingAvg,
    required this.ratingCount,
  });

  factory SellerProfile.fromJson(Map<String, dynamic> j) => SellerProfile(
        id: (j['id'] as num?)?.toInt() ?? 0,
        slug: (j['slug'] as String?) ?? '',
        displayName: (j['display_name'] as String?) ?? '',
        bio: (j['bio'] as String?) ?? '',
        logoImageUrl: j['logo_image_url'] as String?,
        bannerImageUrl: j['banner_image_url'] as String?,
        ratingAvg: (j['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final String slug;
  final String displayName;
  final String bio;
  final String? logoImageUrl;
  final String? bannerImageUrl;
  final double ratingAvg;
  final int ratingCount;
}

/// One review aggregated across a seller's products (GET /sellers/{slug}/reviews).
class SellerReview {
  const SellerReview({
    required this.id,
    required this.productId,
    required this.productTitle,
    required this.rating,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory SellerReview.fromJson(Map<String, dynamic> j) => SellerReview(
        id: (j['id'] as num?)?.toInt() ?? 0,
        productId: (j['product_id'] as num?)?.toInt() ?? 0,
        productTitle: (j['product_title'] as String?) ?? '',
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        createdAt: DateTime.tryParse((j['created_at'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int id;
  final int productId;
  final String productTitle;
  final int rating;
  final String title;
  final String body;
  final DateTime createdAt;
}

/// Thin wrapper over the public seller storefront endpoints (all reads, no auth).
class SellerStorefrontRepository {
  SellerStorefrontRepository(this._dio);

  final Dio _dio;

  Future<SellerProfile> getProfile(String slug) async {
    final resp = await _dio.get<Map<String, dynamic>>('/sellers/$slug');
    return SellerProfile.fromJson(
      (resp.data?['seller'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Future<(List<ProductSummary>, bool)> listProducts(
    String slug, {
    required int page,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/sellers/$slug/products',
      queryParameters: <String, dynamic>{'page': page},
    );
    final data = resp.data ?? const {};
    final items = ((data['data'] as List<dynamic>?) ?? const [])
        .map((e) => sellerProductFromApi(e as Map<String, dynamic>))
        .toList();
    final meta = (data['meta'] as Map<String, dynamic>?) ?? const {};
    final totalPages = (meta['total_pages'] as num?)?.toInt() ?? page;
    return (items, page < totalPages);
  }

  Future<(List<SellerReview>, bool)> listReviews(
    String slug, {
    required int page,
    required int pageSize,
  }) async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/sellers/$slug/reviews',
      queryParameters: <String, dynamic>{'page': page, 'per_page': pageSize},
    );
    final data = resp.data ?? const {};
    final items = ((data['data'] as List<dynamic>?) ?? const [])
        .map((e) => SellerReview.fromJson(e as Map<String, dynamic>))
        .toList();
    final hasMore = (data['hasMore'] as bool?) ?? false;
    return (items, hasMore);
  }
}

/// Maps the shared buildProductSummaryJSON shape (snake_case, cashback key
/// `monthly_amount_minor`) to the generated [ProductSummary] — the generated
/// `fromJson` expects `monthly_coin_minor`, so map explicitly (same trap the
/// recently-viewed rail handles).
ProductSummary sellerProductFromApi(Map<String, dynamic> j) {
  final cb = (j['cashback_preview'] as Map<String, dynamic>?) ?? const {};
  return ProductSummary(
    id: (j['id'] as num).toInt(),
    sellerId: (j['seller_id'] as num?)?.toInt() ?? 0,
    categoryId: (j['category_id'] as num?)?.toInt() ?? 0,
    brand: (j['brand'] as String?) ?? '',
    status: switch (j['status'] as String?) {
      'inactive' => ProductSummaryStatusEnum.inactive,
      'draft' => ProductSummaryStatusEnum.draft,
      _ => ProductSummaryStatusEnum.active,
    },
    title: (j['title'] as String?) ?? '',
    priceMinor: (j['price_minor'] as num?)?.toInt() ?? 0,
    priceCurrency: (j['price_currency'] as String?) ?? '',
    coverImageUrl: j['cover_image_url'] as String?,
    originalPriceMinor: (j['original_price_minor'] as num?)?.toInt(),
    discountPct: (j['discount_pct'] as num?)?.toInt(),
    ratingAvg: (j['rating_avg'] as num?)?.toDouble(),
    ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
    cashbackPreview: CashbackPreview(
      monthlyCoinMinor: (cb['monthly_amount_minor'] as num?)?.toInt() ?? 0,
      currency: (cb['currency'] as String?) ?? '',
    ),
  );
}

final sellerStorefrontRepositoryProvider =
    Provider<SellerStorefrontRepository>(
  (ref) => SellerStorefrontRepository(ref.watch(dioProvider)),
);
