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
import 'package:mopro/features/catalog/screens/search_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// SE-02/03/04/05: SearchScreen ports the PLP screen-level wins — mobile filter
// affordance, result count, infinite-scroll/numbered-pages, 2/3/4/5 grid.

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

class _PagedSearchApi extends SearchApi {
  _PagedSearchApi() : super(Dio());
  final pages = <int>[];

  @override
  Future<Response<ListProducts200Response>> search({
    required String q,
    List<String>? brand,
    int? rating,
    bool? freeShipping,
    bool? inStock,
    bool? priceDropped,
    List<String>? attr,
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

Future<_PagedSearchApi> _pumpQuery(WidgetTester tester, {required double width}) async {
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
  final api = _PagedSearchApi();

  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
      GoRoute(path: '/products/:id', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/categories/:id', builder: (_, __) => const Scaffold()),
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
          searchApiProvider.overrideWithValue(api),
          categoriesProvider.overrideWith(_Cats.new),
        ],
        child: MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
      ),
    ),
  );
  await tester.pump();
  // Type a query, wait out the 300ms debounce + the fetch.
  await tester.enterText(find.byType(TextField).first, 'nike');
  await tester.pump(const Duration(milliseconds: 400));
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

  testWidgets('mobile: filter affordance + result count + no numbered pages',
      (tester) async {
    await _pumpQuery(tester, width: 375);
    expect(find.text('catalog.filter_title'), findsOneWidget); // SE-02 filter button
    expect(find.text('plp.result_count'), findsWidgets); // SE-03 count
    expect(find.byKey(const ValueKey('plp-page-2')), findsNothing); // mobile = infinite
  });

  testWidgets('desktop: numbered pages + count; page jump replaces',
      (tester) async {
    final api = await _pumpQuery(tester, width: 1440);
    expect(find.text('plp.result_count'), findsWidgets); // SE-03
    expect(find.byKey(const ValueKey('plp-page-2')), findsOneWidget); // SE-04
    expect(find.text('catalog.load_more'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('plp-page-2')));
    await tester.pumpAndSettle();
    expect(api.pages.last, 2);
  });
}
