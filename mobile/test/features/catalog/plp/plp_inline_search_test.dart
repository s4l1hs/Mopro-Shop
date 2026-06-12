import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/features/catalog/providers/filtered_products_provider.dart';
import 'package:mopro_api/mopro_api.dart';

// PLP-10: a non-empty inline query swaps FilteredProductsNotifier's source from
// the category listing to the category-scoped /search (and back when cleared).

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 5,
      brand: 'B',
      status: ProductSummaryStatusEnum.active,
      title: 'P$id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      cashbackPreview:
          CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

Response<ListProducts200Response> _resp(List<ProductSummary> data) => Response(
      data: ListProducts200Response(
        data: data,
        pagination:
            PaginationMeta(page: 1, perPage: 20, total: data.length, totalPages: 1),
      ),
      requestOptions: RequestOptions(),
      statusCode: 200,
    );

class _FakeCatalogApi extends CatalogApi {
  _FakeCatalogApi() : super(Dio());
  int listCalls = 0;

  @override
  Future<Response<ListProducts200Response>> listProducts({
    int? minPrice,
    int? maxPrice,
    List<String>? brand,
    int? rating,
    bool? freeShipping,
    bool? inStock,
    bool? priceDropped,
    List<String>? attr,
    String? xTraceId,
    int? categoryId,
    int? page = 1,
    int? perPage = 20,
    String? sort = 'recommended',
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    listCalls++;
    return _resp([_p(1), _p(2)]);
  }
}

class _FakeSearchApi extends SearchApi {
  _FakeSearchApi() : super(Dio());
  String? lastQ;
  int? lastCategoryId;

  @override
  Future<Response<ListProducts200Response>> search({
    required String q,
    String? xTraceId,
    int? categoryId,
    int? page = 1,
    int? perPage = 20,
    int? minPrice,
    int? maxPrice,
    List<String>? brand,
    int? rating,
    bool? freeShipping,
    bool? inStock,
    bool? priceDropped,
    List<String>? attr,
    String? sort = 'recommended',
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    lastQ = q;
    lastCategoryId = categoryId;
    return _resp([_p(3)]);
  }
}

void main() {
  test('inline query routes to category-scoped search and back', () async {
    final catalogApi = _FakeCatalogApi();
    final searchApi = _FakeSearchApi();
    final container = ProviderContainer(overrides: [
      catalogApiProvider.overrideWithValue(catalogApi),
      searchApiProvider.overrideWithValue(searchApi),
    ]);
    addTearDown(container.dispose);

    const key = '5';
    // Keep the family alive for the test's lifetime.
    final sub = container.listen(filteredProductsProvider(key), (_, __) {});
    addTearDown(sub.close);

    // Initial load (empty query) → the category listing.
    await Future<void>.delayed(Duration.zero);
    expect(catalogApi.listCalls, 1);
    expect(searchApi.lastQ, isNull);

    // Set the inline query → notifier rebuilds → category-scoped /search.
    container.read(plpInlineQueryProvider(key).notifier).state = 'tişört';
    await Future<void>.delayed(Duration.zero);
    expect(searchApi.lastQ, 'tişört');
    expect(searchApi.lastCategoryId, 5);
    expect(
      container.read(filteredProductsProvider(key)).products.valueOrNull?.length,
      1,
    );

    // Clear the query → back to the listing.
    container.read(plpInlineQueryProvider(key).notifier).state = '';
    await Future<void>.delayed(Duration.zero);
    expect(catalogApi.listCalls, 2);
  });
}
