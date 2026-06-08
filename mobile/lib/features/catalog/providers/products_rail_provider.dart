import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro_api/mopro_api.dart';

/// Global Home product rail (recommended / bestseller / newest).
///
/// Uses the generated `api.listProducts` with `category_id` omitted → the list
/// handler's global, catalog-wide list (F-020 handler fix). The `/products`
/// response is now OpenAPI-compliant (F-021: `monthly_coin_minor` + `pagination`),
/// so the generated `ListProducts200Response` parse succeeds — the F-020 manual-
/// mapper workaround on this rail is no longer needed.
final productsRailProvider = FutureProvider.autoDispose
    .family<List<ProductSummary>, String>((ref, sort) async {
  final api = ref.read(catalogApiProvider);
  final resp = await api.listProducts(sort: sort, perPage: 6);
  return resp.data?.data ?? [];
});
