import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines are generated on Linux/CI via the golden-rebaseline workflow; the
// platform guard fails these on non-CI platforms with a remediation message.

Variant _v(int id, {String? color, String? size}) => Variant(
      id: id,
      sku: 'SKU$id',
      color: color,
      size: size,
      priceMinor: 12900,
      priceCurrency: 'TRY',
      stock: 10,
      imageUrls: const [],
    );

Product _variantsProduct() => Product(
      id: 1,
      sellerId: 1,
      sellerName: 'Acme Store',
      categoryId: 5,
      brand: 'Acme',
      status: ProductStatusEnum.active,
      title: 'Çok Seçenekli Ürün',
      description: 'Ürün açıklaması.',
      variants: [
        _v(1, color: 'Kırmızı', size: 'M'),
        _v(2, color: 'Mavi', size: 'L'),
        _v(3, color: 'Siyah', size: 'S'),
      ],
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
      createdAt: DateTime.utc(2026),
    );

Product _simpleProduct() => Product(
      id: 2,
      sellerId: 1,
      sellerName: 'Acme Store',
      categoryId: 5,
      brand: 'Acme',
      status: ProductStatusEnum.active,
      title: 'Tek Seçenekli Ürün',
      description: 'Ürün açıklaması.',
      variants: [_v(1)],
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 80, currency: 'TRY_COIN'),
      createdAt: DateTime.utc(2026),
    );

class _FakeCatalogApi extends CatalogApi {
  _FakeCatalogApi(this.product) : super(Dio());
  final Product product;

  @override
  Future<Response<Product>> getProduct({
    required int id,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response(data: product, requestOptions: RequestOptions(), statusCode: 200);

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
          data: const [],
          pagination: PaginationMeta(page: 1, perPage: 20, total: 0, totalPages: 0),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

Future<void> _pump(
  WidgetTester tester, {
  required Product product,
  required Size size,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          catalogApiProvider.overrideWithValue(_FakeCatalogApi(product)),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          home: const ProductDetailScreen(productId: 1),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100)); // buy-box measure settle
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => Directory.systemTemp.path,
      )
      // The PDP watches cartProvider, which reads the auth token from secure
      // storage; stub it so no MissingPluginException is thrown during goldens.
      ..setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => call.method == 'readAll' ? <String, String>{} : null,
      );
    await EasyLocalization.ensureInitialized();
  });

  for (final width in <double>[1024, 1440]) {
    for (final brightness in Brightness.values) {
      final b = brightness == Brightness.dark ? 'dark' : 'light';
      final w = width.toInt();

      testWidgets('pdp two-column variants $w $b', (tester) async {
        await _pump(
          tester,
          product: _variantsProduct(),
          size: Size(width, 1200),
          brightness: brightness,
        );
        await expectLater(
          find.byType(ProductDetailScreen),
          matchesGoldenFile('goldens/pdp_two_col_variants_${w}_$b.png'),
        );
      });

      testWidgets('pdp two-column simple $w $b', (tester) async {
        await _pump(
          tester,
          product: _simpleProduct(),
          size: Size(width, 1200),
          brightness: brightness,
        );
        await expectLater(
          find.byType(ProductDetailScreen),
          matchesGoldenFile('goldens/pdp_two_col_simple_${w}_$b.png'),
        );
      });
    }
  }
}
