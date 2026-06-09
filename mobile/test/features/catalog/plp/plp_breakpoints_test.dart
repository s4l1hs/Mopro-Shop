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
import 'package:mopro/features/catalog/widgets/product_grid.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PLP-19: grid columns 2 (mobile) / 3 (tablet) / 4 (desktop <1440) / 5 (≥1440).

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

class _Api extends CatalogApi {
  _Api() : super(Dio());
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
  }) async =>
      Response(
        data: ListProducts200Response(
          data: [for (var i = 0; i < 8; i++) _p(i + 1)],
          pagination: PaginationMeta(page: 1, perPage: 20, total: 8, totalPages: 1),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

class _Cats extends CategoriesNotifier {
  @override
  CategoriesState build() => const CategoriesState(categories: AsyncData([]));
}

Future<int> _columnsAt(WidgetTester tester, double width) async {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);

  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/categories/5',
    routes: [
      GoRoute(
        path: '/categories/:id',
        builder: (_, __) => const CategoryProductsScreen(
          categoryId: 5,
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
          catalogApiProvider.overrideWithValue(_Api()),
          categoriesProvider.overrideWith(_Cats.new),
        ],
        child: MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<ProductGrid>(find.byType(ProductGrid)).crossAxisCount;
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

  testWidgets('2 cols @375 (mobile)', (t) async => expect(await _columnsAt(t, 375), 2));
  testWidgets('3 cols @768 (tablet)', (t) async => expect(await _columnsAt(t, 768), 3));
  testWidgets('4 cols @1024 (desktop <1440)', (t) async => expect(await _columnsAt(t, 1024), 4));
  testWidgets('5 cols @1440 (ultra-wide)', (t) async => expect(await _columnsAt(t, 1440), 5));
}
