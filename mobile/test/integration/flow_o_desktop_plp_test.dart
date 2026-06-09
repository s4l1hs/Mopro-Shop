import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/plp/widgets/filter_panel.dart';
import 'package:mopro/features/catalog/plp/widgets/plp_filter_chips.dart';
import 'package:mopro/features/catalog/screens/category_products_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

// ── Flow O — desktop PLP filter sidebar URL round-trip ──────────────────────────

ProductSummary _p(int id, String brand) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 42,
      brand: brand,
      status: ProductSummaryStatusEnum.active,
      title: '$brand $id',
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
  }) async =>
      Response(
        data: ListProducts200Response(
          data: [_p(1, 'Adidas'), _p(2, 'Nike')],
          pagination: PaginationMeta(page: 1, perPage: 20, total: 2, totalPages: 1),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

late GoRouter _router;

GoRouter _build() => GoRouter(
      initialLocation: '/categories/42',
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

Uri _uri() => _router.routeInformationProvider.value.uri;

void main() {
  setUpAll(initTestEnv);

  testWidgets('Flow O: check brand → URL+chip; remove chip → URL clears',
      (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);

    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    _router = _build();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          catalogApiProvider.overrideWithValue(_FakeCatalogApi()),
        ],
        child: MaterialApp.router(theme: buildLightTheme(), routerConfig: _router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Sidebar renders.
    expect(find.byType(FilterPanel), findsOneWidget);

    // Check the first brand (Adidas, alphabetical) → after the 300ms debounce
    // the URL carries it.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(_uri().queryParameters['brand'], 'Adidas');

    // Remove it via the chip's delete icon → filter clears (and the URL follows
    // via the same debounced path proven above).
    final closeInChip = find.descendant(
      of: find.byType(PlpFilterChips),
      matching: find.byIcon(Icons.close),
    );
    expect(closeInChip, findsOneWidget);
    await tester.tap(closeInChip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final container =
        ProviderScope.containerOf(tester.element(find.byType(CategoryProductsScreen)));
    expect(
      container.read(plpFiltersProvider(plpKeyForCategory(42))).brands,
      isEmpty,
    );
    expect(_uri().queryParameters.containsKey('brand'), isFalse);
  });
}
