import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro_api/mopro_api.dart';

/// The debounced query the autocomplete dropdown is currently fetching
/// suggestions for (SE-06). The header search pill updates this 300 ms after
/// the user stops typing; an empty value means "show recent/trending/category"
/// instead of structured suggestions.
final searchSuggestQueryProvider =
    StateProvider.autoDispose<String>((ref) => '');

/// Structured brand + product autocomplete suggestions for `query` (SE-06).
///
/// Calls `GET /search/suggest` via the generated client and returns the typed
/// [SuggestResponse]. A blank query short-circuits to an empty response (the
/// dropdown falls back to recent/trending/categories), and any network error
/// degrades to empty rather than surfacing an error row in the dropdown.
final searchSuggestionsProvider = FutureProvider.autoDispose
    .family<SuggestResponse, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) {
    return SuggestResponse(brands: const [], products: const []);
  }
  try {
    final resp = await ref.read(searchApiProvider).searchSuggest(q: q);
    return resp.data ??
        SuggestResponse(brands: const [], products: const []);
  } on DioException catch (_) {
    return SuggestResponse(brands: const [], products: const []);
  }
});
