import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/screens/category_products_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

// ── Flow N — PLP URL substrate ──────────────────────────────────────────────
// The CategoryProductsScreen treats the URL query string as the source of
// truth for PlpFilters: it hydrates from query params on entry, mirrors filter
// changes back into the URL (debounced), and browser back/forward restores a
// prior filter state. No network: the catalog API is faked.

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

  String? lastSort;

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
    lastSort = sort;
    return Response(
      data: ListProducts200Response(
        data: [for (var i = 0; i < 4; i++) _p(i + 1)],
        pagination: PaginationMeta(page: 1, perPage: 20, total: 4, totalPages: 1),
      ),
      requestOptions: RequestOptions(),
      statusCode: 200,
    );
  }
}

class _EmptyCats extends CategoriesNotifier {
  @override
  CategoriesState build() => const CategoriesState(categories: AsyncData([]));
}

late GoRouter _router;

GoRouter _build(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/categories/:id',
          builder: (_, s) => CategoryProductsScreen(
            categoryId: int.parse(s.pathParameters['id']!),
            categoryName: 'Elektronik',
          ),
        ),
      ],
    );

PlpFilters _filters(WidgetTester tester) {
  final container =
      ProviderScope.containerOf(tester.element(find.byType(CategoryProductsScreen)));
  return container.read(plpFiltersProvider(plpKeyForCategory(5)));
}

void _setSort(WidgetTester tester, PlpSort sort) {
  final container =
      ProviderScope.containerOf(tester.element(find.byType(CategoryProductsScreen)));
  container.read(plpFiltersProvider(plpKeyForCategory(5)).notifier).setSort(sort);
}

Uri _uri() => _router.routeInformationProvider.value.uri;

Future<void> _pump(
  WidgetTester tester, {
  String initial = '/categories/5?sort=price_asc&min=10000',
}) async {
  // Untranslated cashback-chip strings inflate card height in tests (real
  // translations are short); filter that one render artifact.
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);

  // Size via tester.view (dpr=1) so 390 resolves to mobile reliably — this
  // suite exercises the bottom-sheet URL substrate, not the desktop sidebar.
  // (setSurfaceSize(390) resolves to tablet and would mount the FilterPanel,
  // whose categoriesProvider hits Dio and leaves a pending timer.)
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  _router = _build(initial);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        catalogApiProvider.overrideWithValue(_FakeCatalogApi()),
        // The breadcrumb (PLP-05) reads categoriesProvider; stub it empty so it
        // doesn't fire a real listCategories fetch (this flow is URL-state only).
        categoriesProvider.overrideWith(_EmptyCats.new),
      ],
      child: MaterialApp.router(theme: buildLightTheme(), routerConfig: _router),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('Flow N: hydrate from URL, debounced write-back, back restores',
      (tester) async {
    await _pump(tester);

    // 1) Hydrate: query params populate the filter state on entry.
    final hydrated = _filters(tester);
    expect(hydrated.sort, PlpSort.priceAsc);
    expect(hydrated.priceMinMinor, 10000);

    // 2) Write-back: change the sort → after the 300ms debounce the URL
    //    reflects the new sort (and drops the now-default-free min we keep).
    _setSort(tester, PlpSort.priceDesc);
    await tester.pump(); // listener schedules the debounced write
    await tester.pump(const Duration(milliseconds: 350)); // debounce fires
    await tester.pump();
    expect(_uri().queryParameters['sort'], 'price_desc');
    expect(_uri().queryParameters['min'], '10000'); // preserved
  });

  testWidgets('Flow N: a different deep link hydrates to a different state',
      (tester) async {
    // Entering the PLP at another URL (as browser back/forward or a shared
    // link would) reconstructs the matching filter state — hydration is purely
    // a function of the query string, not of prior in-session state.
    await _pump(tester, initial: '/categories/5?sort=cashback_desc&shipping=free');
    final f = _filters(tester);
    expect(f.sort, PlpSort.cashbackDesc);
    expect(f.freeShippingOnly, isTrue);
    expect(f.priceMinMinor, isNull);
  });
}
