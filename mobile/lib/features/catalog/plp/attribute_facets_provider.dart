import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro_api/mopro_api.dart';

/// PLP-13: facetable attributes for a category (and its PLP-12 subtree) — each
/// `Facet` carries a slug, a server-localized name, and `(value, count)` buckets.
/// Backed by `GET /categories/{id}/facets` (#160). Family key is the category id;
/// `autoDispose` so it refetches when the category changes. Non-positive ids
/// (e.g. the search mount's `-1`) short-circuit to empty — facets are
/// category-scoped.
final attributeFacetsProvider = FutureProvider.family
    .autoDispose<List<Facet>, int>((ref, categoryId) async {
  if (categoryId <= 0) return const [];
  final api = ref.read(catalogApiProvider);
  final resp = await api.getCategoryFacets(id: categoryId);
  return resp.data?.facets ?? const [];
});
