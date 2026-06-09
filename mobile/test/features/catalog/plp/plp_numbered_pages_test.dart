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

// PLP-15: desktop numbered pages (mobile keeps PLP-03 infinite scroll).

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 5,
      brand: 'B$id',
      status: ProductSummaryStatusEnum.active,
      title: 'Item $id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

class _PagedApi extends CatalogApi {
  _PagedApi() : super(Dio());
  final pages = <int>[];

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
    pages.add(p);
    return Response(
      data: ListProducts200Response(
        data: [for (var i = 0; i < 8; i++) _p((p - 1) * 8 + i + 1)],
        pagination: PaginationMeta(page: p, perPage: 8, total: 24, totalPages: 3),
      ),
      requestOptions: RequestOptions(),
      statusCode: 200,
    );
  }
}

class _Cats extends CategoriesNotifier {
  @override
  CategoriesState build() => const CategoriesState(categories: AsyncData([]));
}

Future<_PagedApi> _pump(WidgetTester tester, {required double width}) async {
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
  final api = _PagedApi();

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
          categoriesProvider.overrideWith(_Cats.new),
        ],
        child: MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
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

  testWidgets('desktop shows numbered pages; tapping a page replaces the grid',
      (tester) async {
    final api = await _pump(tester, width: 1440);
    expect(api.pages, [1]);
    // No load-more button on desktop; numbered control instead.
    expect(find.text('catalog.load_more'), findsNothing);
    expect(find.byKey(const ValueKey('plp-page-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-page-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('plp-page-3')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plp-page-2')));
    await tester.pumpAndSettle();
    expect(api.pages.last, 2); // jumped to page 2 (replace, not append)
  });

  testWidgets('mobile shows no numbered pages (infinite scroll path)',
      (tester) async {
    await _pump(tester, width: 375);
    expect(find.byKey(const ValueKey('plp-page-2')), findsNothing);
  });
}
