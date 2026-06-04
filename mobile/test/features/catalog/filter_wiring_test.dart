import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/providers/filtered_products_provider.dart';
import 'package:mopro/features/catalog/providers/search_provider.dart';
import 'package:mopro_api/mopro_api.dart';

// P-026: verify the wired filter/sort state flows from plpFiltersProvider through
// the fetch providers into the catalog/search API calls (the dimensions P-028
// shipped). Provider-level tests with capturing fakes — no widgets, no i18n.

Response<ListProducts200Response> _emptyPage(int page) => Response(
      data: ListProducts200Response(
        data: const [],
        pagination:
            PaginationMeta(page: page, perPage: 20, total: 0, totalPages: 1),
      ),
      requestOptions: RequestOptions(),
      statusCode: 200,
    );

class _CapturingCatalogApi extends CatalogApi {
  _CapturingCatalogApi() : super(Dio());

  int callCount = 0;
  int? catId;
  String? sort;
  int? minPrice;
  int? maxPrice;
  List<String>? brand;
  int? rating;
  bool? freeShipping;
  bool? inStock;

  @override
  Future<Response<ListProducts200Response>> listProducts({
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
    String? sort = 'recommended',
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    callCount++;
    catId = categoryId;
    this.sort = sort;
    this.minPrice = minPrice;
    this.maxPrice = maxPrice;
    this.brand = brand;
    this.rating = rating;
    this.freeShipping = freeShipping;
    this.inStock = inStock;
    return _emptyPage(page ?? 1);
  }
}

class _CapturingSearchApi extends SearchApi {
  _CapturingSearchApi() : super(Dio());

  String? q;
  String? sort;
  int? rating;
  bool? freeShipping;
  int? minPrice;

  @override
  Future<Response<ListProducts200Response>> search({
    required String q,
    List<String>? brand,
    int? rating,
    bool? freeShipping,
    bool? inStock,
    String? xTraceId,
    int? categoryId,
    int? minPrice,
    int? maxPrice,
    String? sort = 'recommended',
    int? page = 1,
    int? perPage = 20,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    this.q = q;
    this.sort = sort;
    this.rating = rating;
    this.freeShipping = freeShipping;
    this.minPrice = minPrice;
    return _emptyPage(page ?? 1);
  }
}

void main() {
  group('PLP filter wiring', () {
    test('passes every active filter dimension to listProducts', () async {
      final api = _CapturingCatalogApi();
      final container = ProviderContainer(
        overrides: [catalogApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      container.read(plpFiltersProvider('5').notifier).set(
            const PlpFilters(
              sort: PlpSort.priceDesc,
              priceMinMinor: 1500,
              priceMaxMinor: 9000,
              brands: ['Nike', 'Adidas'],
              ratingMin: 4,
              freeShippingOnly: true,
              inStock: true,
            ),
          );
      // build() captures the filter; refresh() awaits the load deterministically.
      container.read(filteredProductsProvider('5'));
      await container.read(filteredProductsProvider('5').notifier).refresh();

      expect(api.catId, 5);
      expect(api.sort, 'price_desc');
      expect(api.minPrice, 1500);
      expect(api.maxPrice, 9000);
      expect(api.brand, ['Nike', 'Adidas']);
      expect(api.rating, 4);
      expect(api.freeShipping, isTrue);
      expect(api.inStock, isTrue);
    });

    test('omits unset filters (empty/false -> null, default sort)', () async {
      final api = _CapturingCatalogApi();
      final container = ProviderContainer(
        overrides: [catalogApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      container.read(filteredProductsProvider('7'));
      await container.read(filteredProductsProvider('7').notifier).refresh();

      expect(api.sort, 'recommended');
      expect(api.minPrice, isNull);
      expect(api.maxPrice, isNull);
      expect(api.brand, isNull);
      expect(api.rating, isNull);
      expect(api.freeShipping, isNull);
      expect(api.inStock, isNull);
    });

    test('refetches when a filter changes', () async {
      final api = _CapturingCatalogApi();
      final container = ProviderContainer(
        overrides: [catalogApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(filteredProductsProvider('9'), (_, __) {});
      addTearDown(sub.close);
      await container.read(filteredProductsProvider('9').notifier).refresh();
      final before = api.callCount;

      container
          .read(plpFiltersProvider('9').notifier)
          .update((f) => f.copyWith(ratingMin: 3));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(api.callCount, greaterThan(before));
      expect(api.rating, 3);
    });
  });

  group('Search filter wiring', () {
    test('passes filter dimensions to search()', () async {
      final api = _CapturingSearchApi();
      final container = ProviderContainer(
        overrides: [searchApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      container.read(plpFiltersProvider(plpKeyForSearch('elbise')).notifier).set(
            const PlpFilters(
              sort: PlpSort.newest,
              ratingMin: 5,
              freeShippingOnly: true,
              priceMinMinor: 2000,
            ),
          );
      container.read(searchProvider.notifier).setQuery('elbise');
      // setQuery debounces 300 ms before fetching.
      await Future<void>.delayed(const Duration(milliseconds: 360));

      expect(api.q, 'elbise');
      expect(api.sort, 'newest');
      expect(api.rating, 5);
      expect(api.freeShipping, isTrue);
      expect(api.minPrice, 2000);
    });
  });
}
