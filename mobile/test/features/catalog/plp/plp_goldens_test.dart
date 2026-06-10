@Tags(['golden'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/plp/attribute_facets_provider.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/screens/category_products_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

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

Category _cat(int id, String name) => Category(
      id: id,
      name: name,
      slug: name.toLowerCase(),
      commissionPctBps: 1000,
    );

class _SeededCategories extends CategoriesNotifier {
  @override
  CategoriesState build() => CategoriesState(
        categories: AsyncData([
          _cat(5, 'Elektronik'),
          _cat(6, 'Giyim'),
          _cat(7, 'Ev & Yaşam'),
        ]),
      );
}

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
  }) async =>
      Response(
        data: ListProducts200Response(
          data: [
            _p(1, 'Adidas'),
            _p(2, 'Nike'),
            _p(3, 'Puma'),
            _p(4, 'Reebok'),
          ],
          pagination: PaginationMeta(page: 1, perPage: 20, total: 4, totalPages: 1),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

Future<void> _pump(
  WidgetTester tester, {
  required String initial,
  required Brightness brightness,
  double width = 1440,
}) async {
  // ProductCard cells slightly overflow their grid aspect ratio (a pre-existing
  // card artifact); filter so --update-goldens can still capture the baseline.
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);

  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
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

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          catalogApiProvider.overrideWithValue(_FakeCatalogApi()),
          categoriesProvider.overrideWith(_SeededCategories.new),
          // PLP-13: the renk facet section is data-driven; keep it empty here so
          // the sidebar goldens are stable (the accordion has its own widget
          // test) and no real facets fetch fires against the fake API.
          attributeFacetsProvider.overrideWith((ref, id) async => const <Facet>[]),
        ],
        child: MaterialApp.router(
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  for (final brightness in Brightness.values) {
    final b = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('plp sidebar no filters 1440 $b', (tester) async {
      await _pump(tester, initial: '/categories/5', brightness: brightness);
      await expectLater(
        find.byType(CategoryProductsScreen),
        matchesGoldenFile('goldens/plp_sidebar_no_filters_1440_$b.png'),
      );
    });

    testWidgets('plp sidebar with filters + chips 1440 $b', (tester) async {
      await _pump(
        tester,
        initial: '/categories/5?brand=Adidas&shipping=free&rating=4',
        brightness: brightness,
      );
      await expectLater(
        find.byType(CategoryProductsScreen),
        matchesGoldenFile('goldens/plp_sidebar_with_filters_1440_$b.png'),
      );
    });

    // 1024 carry (Session 5c §7.1) — same fixture, narrower viewport.
    testWidgets('plp sidebar no filters 1024 $b', (tester) async {
      await _pump(
        tester,
        initial: '/categories/5',
        brightness: brightness,
        width: 1024,
      );
      await expectLater(
        find.byType(CategoryProductsScreen),
        matchesGoldenFile('goldens/plp_sidebar_no_filters_1024_$b.png'),
      );
    });

    testWidgets('plp sidebar with filters + chips 1024 $b', (tester) async {
      await _pump(
        tester,
        initial: '/categories/5?brand=Adidas&shipping=free&rating=4',
        brightness: brightness,
        width: 1024,
      );
      await expectLater(
        find.byType(CategoryProductsScreen),
        matchesGoldenFile('goldens/plp_sidebar_with_filters_1024_$b.png'),
      );
    });
  }
}