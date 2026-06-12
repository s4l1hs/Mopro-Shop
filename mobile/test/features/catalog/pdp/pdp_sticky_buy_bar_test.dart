import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_sticky_buy_bar.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_support/test_harness.dart';

// PD-09: the condensed sticky buy-bar slides in on the wide layout once the
// buy-box column scrolls out of view, and hides again at the top. Mirrors the
// sticky-gallery test's harness (same fake catalog, same drag mechanics).

Variant _v(int id, List<String> imgs, {String color = 'Kırmızı'}) => Variant(
      id: id,
      sku: 'SKU$id',
      color: color,
      size: 'M',
      priceMinor: 12900,
      priceCurrency: 'TRY',
      stock: 10,
      imageUrls: imgs,
    );

Product _product() => Product(
      id: 123,
      sellerId: 1,
      sellerName: 'Acme Store',
      categoryId: 5,
      brand: 'Acme',
      status: ProductStatusEnum.active,
      attributes: const [],
      title: 'Test Ürünü',
      // Long description → tall below-the-fold content so the page can scroll
      // far past the buy-box.
      description: List.filled(60, 'Lorem ipsum dolor sit amet.').join('\n\n'),
      variants: [
        _v(1, ['https://x.test/a.png']),
        for (var i = 2; i <= 8; i++)
          _v(i, ['https://x.test/$i.png'], color: 'Renk$i'),
      ],
      cashbackPreview:
          CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
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
      Response(
        data: _product(),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );

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
          pagination:
              PaginationMeta(page: 1, perPage: 20, total: 0, totalPages: 0),
        ),
        requestOptions: RequestOptions(),
        statusCode: 200,
      );
}

// The bar wraps itself in Offstage while hidden, so default finders (which
// skip offstage) see its content only when it is actually revealed.
Finder _barContent() => find.descendant(
      of: find.byType(PdpStickyBuyBar),
      matching: find.byType(FilledButton),
    );

Future<void> _drag(WidgetTester tester, double dy) async {
  await tester.dragFrom(const Offset(900, 300), Offset(0, dy));
  await tester.pump();
  await tester.pump();
}

Future<void> _pump(WidgetTester tester) async {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);

  tester.view.physicalSize = const Size(1080, 900);
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
  await tester.pump(const Duration(milliseconds: 50)); // buy-box measure
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('buy-bar hidden at top, appears past the buy-box, hides again',
      (tester) async {
    await _pump(tester);

    // At scroll origin the bar is offstage (hidden) — its CTA is not findable.
    expect(_barContent(), findsNothing,
        reason: 'buy-bar must be hidden while the buy-box is on screen',);

    // Scroll well past the buy-box column → bar slides in with the CTA.
    await _drag(tester, -2000);
    await tester.pump(const Duration(milliseconds: 250));
    expect(_barContent(), findsOneWidget,
        reason: 'buy-bar must appear once the buy-box scrolls out of view',);

    // Back to the top → hidden again.
    await _drag(tester, 2030);
    await tester.pump(const Duration(milliseconds: 250));
    expect(_barContent(), findsNothing,
        reason: 'buy-bar must hide again at the scroll origin',);
  });
}
