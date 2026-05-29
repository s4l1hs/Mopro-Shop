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

import '../../../_support/test_harness.dart';

ProductSummary _p(int id, String brand) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 5,
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
          data: [_p(1, 'Adidas'), _p(2, 'Nike'), _p(3, 'Puma')],
          pagination: PaginationMeta(page: 1, perPage: 20, total: 3, totalPages: 1),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

GoRouter _router() => GoRouter(
      initialLocation: '/categories/5',
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

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(CategoryProductsScreen)));

Future<void> _pump(WidgetTester tester, Size size) async {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        catalogApiProvider.overrideWithValue(_FakeCatalogApi()),
      ],
      child: MaterialApp.router(theme: buildLightTheme(), routerConfig: _router()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('sidebar renders at >=768 and not below', (tester) async {
    await _pump(tester, const Size(1440, 1000));
    expect(find.byType(FilterPanel), findsOneWidget);

    await _pump(tester, const Size(375, 900));
    expect(find.byType(FilterPanel), findsNothing);
  });

  testWidgets('brand search filters the visible brand list', (tester) async {
    await _pump(tester, const Size(1440, 1000));
    expect(find.text('Adidas'), findsOneWidget);
    expect(find.text('Nike'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'adi');
    await tester.pump();
    expect(find.text('Adidas'), findsOneWidget);
    expect(find.text('Nike'), findsNothing);
  });

  testWidgets('checking a brand adds a chip + writes the filter', (tester) async {
    await _pump(tester, const Size(1440, 1000));
    await tester.tap(find.byType(Checkbox).first); // Adidas (alphabetical)
    await tester.pump();

    final f = _container(tester).read(plpFiltersProvider(plpKeyForCategory(5)));
    expect(f.brands, contains('Adidas'));
    expect(find.byType(PlpFilterChips), findsOneWidget);
    expect(find.textContaining('Adidas'), findsWidgets);
  });

  testWidgets('clear-all resets every filter', (tester) async {
    await _pump(tester, const Size(1440, 1000));
    _container(tester)
        .read(plpFiltersProvider(plpKeyForCategory(5)).notifier)
        .update((f) => f.copyWith(brands: ['Nike'], freeShippingOnly: true));
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'plp.clear_all'));
    await tester.pump();

    final f = _container(tester).read(plpFiltersProvider(plpKeyForCategory(5)));
    expect(f.isEmpty, isTrue);
  });
}
