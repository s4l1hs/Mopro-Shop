import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/features/catalog/data/product_summary_api.dart';
import 'package:mopro_api/mopro_api.dart';

/// Global Home product rail (recommended / bestseller / newest).
///
/// Fetches the raw `/products` response and maps each item with the shared
/// [productSummaryFromApi] — the SAME path the working recommendations rail
/// uses — instead of the generated `api.listProducts`. The backend's
/// `buildProductSummaryJSON` shape emits `cashback_preview.monthly_amount_minor`
/// (and a `meta` envelope), which the generated `ListProducts200Response` /
/// `ProductSummary.fromJson` (which require `monthly_coin_minor` / `pagination`)
/// cannot deserialize — that strict-parse throw is why these rails rendered
/// empty (F-020). `category_id` is omitted: the list handler now serves a
/// global, catalog-wide list when it is absent.
///
/// Defensive (CONTRIBUTING, matching the recommendations rail): a fetch/parse
/// error resolves to an empty list so the rail hides rather than surfacing an
/// error on Home.
final productsRailProvider = FutureProvider.autoDispose
    .family<List<ProductSummary>, String>((ref, sort) async {
  try {
    final resp = await ref.read(dioProvider).get<Map<String, dynamic>>(
      '/products',
      queryParameters: <String, dynamic>{'sort': sort, 'per_page': 6},
    );
    final data = (resp.data?['data'] as List<dynamic>?) ?? const [];
    return data
        .map((e) => productSummaryFromApi(e as Map<String, dynamic>))
        .toList();
  } catch (_) {
    return const [];
  }
});
