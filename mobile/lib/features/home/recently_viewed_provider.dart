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
      // GET /me/recently-viewed returns the shared buildProductSummaryJSON shape,
      // now OpenAPI-compliant (F-021), so the generated parse handles it directly.
      final products = data
          .map((e) => ProductSummary.fromJson(e as Map<String, dynamic>))
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

final recentlyViewedProvider =
    NotifierProvider<RecentlyViewedNotifier, AsyncValue<List<ProductSummary>>>(
  RecentlyViewedNotifier.new,
);
