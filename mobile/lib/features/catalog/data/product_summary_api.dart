import 'package:mopro_api/mopro_api.dart';

/// Maps a hand-written core-svc product shape (snake_case, with
/// `cashback_preview.monthly_amount_minor`) into the generated [ProductSummary].
///
/// The hand-written read endpoints (`/me/recently-viewed`,
/// `/recommendations/home`, `/products/{id}/similar`) all emit the shared
/// `buildProductSummaryJSON` shape, whose cashback key is `monthly_amount_minor`
/// — which the generated `ProductSummary.fromJson` (expects a required
/// `monthly_coin_minor`) cannot parse. Hence this explicit mapper, shared across
/// every consumer of that shape.
ProductSummary productSummaryFromApi(Map<String, dynamic> j) {
  final cb = (j['cashback_preview'] as Map<String, dynamic>?) ?? const {};
  return ProductSummary(
    id: (j['id'] as num).toInt(),
    sellerId: (j['seller_id'] as num?)?.toInt() ?? 0,
    categoryId: (j['category_id'] as num?)?.toInt() ?? 0,
    brand: (j['brand'] as String?) ?? '',
    status: productSummaryStatusFromApi(j['status'] as String?),
    title: (j['title'] as String?) ?? '',
    priceMinor: (j['price_minor'] as num?)?.toInt() ?? 0,
    priceCurrency: (j['price_currency'] as String?) ?? '',
    coverImageUrl: j['cover_image_url'] as String?,
    originalPriceMinor: (j['original_price_minor'] as num?)?.toInt(),
    discountPct: (j['discount_pct'] as num?)?.toInt(),
    ratingAvg: (j['rating_avg'] as num?)?.toDouble(),
    ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
    favoritesCount: (j['favorites_count'] as num?)?.toInt() ?? 0,
    freeShipping: (j['free_shipping'] as bool?) ?? false,
    lowest30dPriceMinor: (j['lowest_30d_price_minor'] as num?)?.toInt(),
    cashbackPreview: CashbackPreview(
      monthlyCoinMinor: (cb['monthly_amount_minor'] as num?)?.toInt() ?? 0,
      currency: (cb['currency'] as String?) ?? '',
    ),
  );
}

/// Maps the API status string into the generated enum (defaults to active).
ProductSummaryStatusEnum productSummaryStatusFromApi(String? s) => switch (s) {
      'inactive' => ProductSummaryStatusEnum.inactive,
      'draft' => ProductSummaryStatusEnum.draft,
      _ => ProductSummaryStatusEnum.active,
    };
