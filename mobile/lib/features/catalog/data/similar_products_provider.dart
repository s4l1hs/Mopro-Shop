import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro_api/mopro_api.dart';

/// Co-view recommendations for the PDP "Benzer ürünler" rail, keyed by product
/// id (feat/recommendation-surfaces). Backed by GET /products/{id}/similar,
/// which already pads with global popularity when co-view data is sparse, so the
/// list is rarely empty for a real product.
///
/// Defensive layering (CONTRIBUTING): a fetch error resolves to an **empty
/// list**, never an error state — the PDP must render even when the rail cannot.
/// An empty list hides the rail.
final similarProductsProvider =
    FutureProvider.family<List<ProductSummary>, int>((ref, productId) async {
  try {
    final resp = await ref.read(dioProvider).get<Map<String, dynamic>>(
      '/products/$productId/similar',
      queryParameters: <String, dynamic>{'limit': 12},
    );
    final data = (resp.data?['data'] as List<dynamic>?) ?? const [];
    return data
        .map((e) => ProductSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return const [];
  }
});
