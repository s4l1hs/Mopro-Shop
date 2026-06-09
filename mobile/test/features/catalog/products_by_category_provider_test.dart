import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/features/catalog/providers/products_by_category_provider.dart';
import 'package:mopro_api/mopro_api.dart';

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 5,
      brand: 'B',
      status: ProductSummaryStatusEnum.active,
      title: 'P$id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

class _FakeCatalogApi extends CatalogApi {
  _FakeCatalogApi() : super(Dio());

  @override
  Future<Response<ListProducts200Response>> listProducts({
    int? minPrice,
    int? maxPrice,
    List<String>? brand,
    int? rating,
    bool? freeShipping,
    bool? inStock,
    bool? priceDropped,
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
    return Response(
      data: ListProducts200Response(
        data: [for (var i = 0; i < 3; i++) _p(i + 1)],
        pagination: PaginationMeta(page: 1, perPage: 20, total: 3, totalPages: 1),
      ),
      requestOptions: RequestOptions(),
      statusCode: 200,
    );
  }
}

void main() {
  // Regression: build() must not mutate `state` before the notifier is mounted.
  // The previous implementation called `_load(1, replace: true)` synchronously
  // from build(), and `_load` set `state = AsyncLoading()` before its first
  // await — which threw "Tried to read the state of an uninitialized provider"
  // on the very first read. The fix defers `_load` via Future.microtask.
  test('first read builds without throwing and returns loading', () {
    final container = ProviderContainer(
      overrides: [catalogApiProvider.overrideWithValue(_FakeCatalogApi())],
    );
    addTearDown(container.dispose);

    late ProductsState initial;
    expect(
      () => initial = container.read(productsByCategoryProvider(5)),
      returnsNormally,
    );
    expect(initial.products, isA<AsyncLoading<List<ProductSummary>>>());
  });

  test('deferred load resolves to the fetched products', () async {
    final container = ProviderContainer(
      overrides: [catalogApiProvider.overrideWithValue(_FakeCatalogApi())],
    );
    addTearDown(container.dispose);

    // Build the notifier, then await the (deferred) initial load.
    container.read(productsByCategoryProvider(5));
    await container.read(productsByCategoryProvider(5).notifier).refresh();

    final after = container.read(productsByCategoryProvider(5));
    expect(after.products.valueOrNull, hasLength(3));
  });
}
