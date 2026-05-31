import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/feature_flags.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';
import 'package:mopro_api/mopro_api.dart';

/// Recently-viewed products for the "Son baktıkların" home rail (Tranche 4c).
///
/// Eligibility gates (all must hold, else empty → rail hides): build flag on,
/// user authed, analytics consent on. Defensive layering (CONTRIBUTING): a fetch
/// error resolves to **empty data**, never an error state — recently-viewed is a
/// non-critical surface and must not propagate failure into the home screen.
///
/// Rebuilds automatically on auth + consent state changes (both `watch`-ed).
class RecentlyViewedNotifier extends Notifier<AsyncValue<List<ProductSummary>>> {
  @override
  AsyncValue<List<ProductSummary>> build() {
    final authed =
        ref.watch(authNotifierProvider).valueOrNull is AuthAuthenticated;
    final consent = ref.watch(userConsentProvider);

    if (!kAnalyticsConsentEnabled || !authed || !consent.analyticsEnabled) {
      return const AsyncValue.data([]);
    }

    Future<void>.microtask(_load);
    return const AsyncValue.loading();
  }

  Future<void> _load() async {
    try {
      final resp = await ref.read(dioProvider).get<Map<String, dynamic>>(
        '/me/recently-viewed',
        queryParameters: <String, dynamic>{'limit': 20},
      );
      final data = (resp.data?['data'] as List<dynamic>?) ?? const [];
      // The hand-written GET /me/recently-viewed returns the shared
      // buildProductSummaryJSON shape (cashback key `monthly_amount_minor`),
      // which the generated ProductSummary.fromJson (expects `monthly_coin_minor`,
      // required) cannot parse — so map explicitly here.
      final products = data
          .map((e) => _summaryFromApi(e as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(products);
    } catch (_) {
      // Non-critical: hide the rail rather than surface an error.
      state = const AsyncValue.data([]);
    }
  }

  /// Re-fetches (used after merge-on-auth identify + after RTBF erase).
  void refresh() => ref.invalidateSelf();
}

/// Maps the hand-written `/me/recently-viewed` product shape (snake_case,
/// `cashback_preview.monthly_amount_minor`) into the generated [ProductSummary].
ProductSummary _summaryFromApi(Map<String, dynamic> j) {
  final cb = (j['cashback_preview'] as Map<String, dynamic>?) ?? const {};
  return ProductSummary(
    id: (j['id'] as num).toInt(),
    sellerId: (j['seller_id'] as num?)?.toInt() ?? 0,
    categoryId: (j['category_id'] as num?)?.toInt() ?? 0,
    brand: (j['brand'] as String?) ?? '',
    status: _statusFromApi(j['status'] as String?),
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

ProductSummaryStatusEnum _statusFromApi(String? s) => switch (s) {
      'inactive' => ProductSummaryStatusEnum.inactive,
      'draft' => ProductSummaryStatusEnum.draft,
      _ => ProductSummaryStatusEnum.active,
    };

final recentlyViewedProvider =
    NotifierProvider<RecentlyViewedNotifier, AsyncValue<List<ProductSummary>>>(
  RecentlyViewedNotifier.new,
);
