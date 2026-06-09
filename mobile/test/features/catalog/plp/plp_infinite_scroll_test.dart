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
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/screens/category_products_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PLP-03: mobile PLP auto-loads the next page near the bottom (no button);
// desktop keeps the explicit "load more" button.

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 5,
      brand: 'B$id',
      status: ProductSummaryStatusEnum.active,
      title: 'P$id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

class _PagedCatalogApi extends CatalogApi {
  _PagedCatalogApi() : super(Dio());

  final pagesRequested = <int>[];

  @override
  Future<Response<ListProducts200Response>> listProducts({
    int? minPrice,
    int? maxPrice,
    List<String>? brand,
    int? rating,
    bool? freeShipping,
    bool? inStock,
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
    final p = page ?? 1;
    pagesRequested.add(p);
    return Response(
      data: ListProducts200Response(
        data: [for (var i = 0; i < 8; i++) _p((p - 1) * 8 + i + 1)],
        // 2 pages total → page 1 hasMore, page 2 is the end.
        pagination: PaginationMeta(page: p, perPage: 8, total: 16, totalPages: 2),
      ),
      requestOptions: RequestOptions(),
      statusCode: 200,
    );
  }
}

Future<_PagedCatalogApi> _pump(WidgetTester tester, {required double width}) async {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);

  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final api = _PagedCatalogApi();

  final router = GoRouter(
    initialLocation: '/categories/5',
    routes: [
      GoRoute(
        path: '/categories/:id',
        builder: (_, s) => CategoryProductsScreen(
          categoryId: int.parse(s.pathParameters['id']!),
          categoryName: 'Elektronik',
        ),
      ),
      GoRoute(path: '/products/:id', builder: (_, __) => const Scaffold()),
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
          catalogApiProvider.overrideWithValue(api),
          categoriesProvider.overrideWith(_SeededCategories.new),
        ],
        child: MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

class _SeededCategories extends CategoriesNotifier {
  @override
  CategoriesState build() =>
      CategoriesState(categories: AsyncData([Category(id: 5, name: 'E', slug: 'e', commissionPctBps: 1000)]));
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

  testWidgets('mobile: no load-more button; scroll near bottom fetches page 2 once',
      (tester) async {
    final api = await _pump(tester, width: 375);
    expect(api.pagesRequested, [1]);
    // Mobile uses infinite scroll — the explicit button is gone.
    expect(find.text('catalog.load_more'), findsNothing);

    // Target the grid's vertical scroller specifically — the breadcrumb adds a
    // horizontal SingleChildScrollView, so `Scrollable.first` is ambiguous.
    final scrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    await tester.drag(scrollable, const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(api.pagesRequested, [1, 2]); // exactly one extra fetch
    expect(api.pagesRequested.where((p) => p == 2).length, 1); // no duplicate

    // At the end (hasMore == false) further scrolling fetches nothing.
    await tester.drag(scrollable, const Offset(0, -4000));
    await tester.pumpAndSettle();
    expect(api.pagesRequested, [1, 2]);
  });

  testWidgets('desktop: keeps the explicit load-more button', (tester) async {
    await _pump(tester, width: 1440);
    expect(find.text('catalog.load_more'), findsOneWidget);
  });
}
