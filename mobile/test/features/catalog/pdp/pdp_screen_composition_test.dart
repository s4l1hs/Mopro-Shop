import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/analytics/analytics_service.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_image_pager.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_seller_card.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_sticky_cta.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_support/test_harness.dart';

Variant _v(int id, {String color = 'Kırmızı', String size = 'M'}) => Variant(
      id: id,
      sku: 'SKU$id',
      color: color,
      size: size,
      priceMinor: 12900,
      priceCurrency: 'TRY',
      stock: 10,
      imageUrls: ['https://x.test/$id.png'],
    );

Product _product() => Product(
      id: 123,
      sellerId: 1,
      sellerName: 'Acme Store',
      categoryId: 5,
      brand: 'Acme',
      status: ProductStatusEnum.active,
      attributes: [
        ProductAttribute(slug: 'renk', name: 'Renk', values: const ['Siyah', 'Beyaz']),
      ],
      title: 'Test Ürünü',
      description: 'Açıklama',
      variants: [_v(1), _v(2, color: 'Mavi', size: 'L')],
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
      createdAt: DateTime.utc(2026),
    );

class _FakeCatalogApi extends CatalogApi {
  _FakeCatalogApi() : super(Dio());

  @override
  Future<Response<Product>> getProduct({
    required int id,
    String? destCity,
    String? xTraceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response(data: _product(), requestOptions: RequestOptions(), statusCode: 200);

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
          data: const [],
          pagination: PaginationMeta(page: 1, perPage: 20, total: 0, totalPages: 0),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

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
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const ProductDetailScreen(productId: 123),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('desktop renders two-column buy-box (pager + seller + CTAs, no sticky)',
      (tester) async {
    await _pump(tester, const Size(1440, 1200));

    expect(find.byType(PdpImagePager), findsOneWidget);
    expect(find.byType(PdpSellerCard), findsOneWidget);
    // Buy-box CTAs.
    expect(find.widgetWithText(FilledButton, 'product.add_to_cart'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'product.add_to_favorites'),
      findsOneWidget,
    );
    // Mobile-only sticky CTA must be absent on desktop.
    expect(find.byType(PdpStickyCta), findsNothing);
  });

  testWidgets('mobile keeps the single-column sticky CTA (no pager)',
      (tester) async {
    await _pump(tester, const Size(375, 900));
    expect(find.byType(PdpStickyCta), findsOneWidget);
    expect(find.byType(PdpImagePager), findsNothing);
  });

  testWidgets('specs tab renders Product.attributes (PD-01 / PLP-13)',
      (tester) async {
    await _pump(tester, const Size(390, 1400));
    // Switch to the specs tab (i18n returns the key in tests).
    await tester.tap(find.text('product.specs_tab').first);
    await tester.pumpAndSettle();
    // Attribute name + comma-joined values are real data (not i18n keys).
    expect(find.text('Renk'), findsOneWidget);
    expect(find.text('Siyah, Beyaz'), findsOneWidget);
  });

  testWidgets('PDP emits product_view with the product categoryId (P-033)',
      (tester) async {
    final captured = <AnalyticsEvent>[];
    final analytics = AnalyticsService(
      sessionId: 'test-sess',
      gate: () => true,
      sink: (_, batch) async => captured.addAll(batch),
      batchSize: 1, // flush each event immediately
      flushInterval: const Duration(milliseconds: 10),
    );
    addTearDown(analytics.dispose);

    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
    tester.view.physicalSize = const Size(390, 1400);
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
          analyticsServiceProvider.overrideWithValue(analytics),
        ],
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const ProductDetailScreen(productId: 123),
        ),
      ),
    );
    await tester.pump(); // resolve the product fetch
    await tester.pump(const Duration(milliseconds: 50)); // post-frame product_view emit
    await analytics.flush();

    final pv = captured.where((e) => e.type == 'product_view').toList();
    expect(pv, isNotEmpty, reason: 'PDP must emit a product_view on mount');
    expect(pv.first.payload['productId'], 123);
    expect(pv.first.payload['categoryId'], 5); // _product().categoryId
  });
}
