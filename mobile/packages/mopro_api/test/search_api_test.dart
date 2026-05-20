import 'package:test/test.dart';
import 'package:mopro_api/mopro_api.dart';


/// tests for SearchApi
void main() {
  final instance = MoproApi().getSearchApi();

  group(SearchApi, () {
    // Full-text product search with filters
    //
    //Future<ListProducts200Response> search(String q, { String xTraceId, int categoryId, int minPrice, int maxPrice, String sort, int page, int perPage }) async
    test('test search', () async {
      // TODO
    });

    // Autocomplete suggestions (debounce 250 ms on client)
    //
    //Future<SearchSuggest200Response> searchSuggest(String q, { String xTraceId }) async
    test('test searchSuggest', () async {
      // TODO
    });

    // Current trending search terms
    //
    //Future<SearchTrending200Response> searchTrending({ String xTraceId }) async
    test('test searchTrending', () async {
      // TODO
    });

  });
}
