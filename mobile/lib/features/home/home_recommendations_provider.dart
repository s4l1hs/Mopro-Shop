import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro_api/mopro_api.dart';

/// Result of GET /recommendations/home: the products plus which variant the
/// backend served. `personalized` (source=="personalized") means co-view recs
/// from the user's own history; otherwise it is the popularity fallback — the
/// home rail uses this to pick its title ("Senin için seçtiklerimiz" vs
/// "Popüler ürünler").
class HomeRecommendations {
  const HomeRecommendations({required this.products, required this.personalized});

  final List<ProductSummary> products;
  final bool personalized;

  static const empty = HomeRecommendations(products: [], personalized: false);
}

/// "Senin için seçtiklerimiz" / "Popüler ürünler" home rail data
/// (feat/recommendation-surfaces).
///
/// Unlike recently-viewed, this rail is shown for **everyone**: guests and
/// non-consenting users get the popularity fallback (the backend decides). We
/// only `watch` auth so logging in/out re-fetches (popular ↔ personalized).
///
/// Defensive layering (CONTRIBUTING): a fetch error resolves to **empty data**,
/// never an error state — the home screen must not surface recommendation
/// failures. An empty list hides the rail (zero space).
class HomeRecommendationsNotifier
    extends Notifier<AsyncValue<HomeRecommendations>> {
  @override
  AsyncValue<HomeRecommendations> build() {
    // Re-fetch when auth state changes (guest popular ↔ personalized).
    ref.watch(authNotifierProvider);
    Future<void>.microtask(_load);
    return const AsyncValue.loading();
  }

  Future<void> _load() async {
    try {
      final resp = await ref.read(dioProvider).get<Map<String, dynamic>>(
        '/recommendations/home',
        queryParameters: <String, dynamic>{'limit': 20},
      );
      final data = (resp.data?['data'] as List<dynamic>?) ?? const [];
      final products = data
          .map((e) => ProductSummary.fromJson(e as Map<String, dynamic>))
          .toList();
      final personalized = resp.data?['source'] == 'personalized';
      state = AsyncValue.data(
        HomeRecommendations(products: products, personalized: personalized),
      );
    } catch (_) {
      // Non-critical surface: hide the rail rather than propagate the error.
      state = const AsyncValue.data(HomeRecommendations.empty);
    }
  }

  void refresh() => ref.invalidateSelf();
}

final homeRecommendationsProvider = NotifierProvider<HomeRecommendationsNotifier,
    AsyncValue<HomeRecommendations>>(
  HomeRecommendationsNotifier.new,
);
