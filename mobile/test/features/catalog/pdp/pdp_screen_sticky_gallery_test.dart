import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_image_pager.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_support/test_harness.dart';

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
      // *past* the pin window and the gallery actually releases.
      description: List.filled(60, 'Lorem ipsum dolor sit amet.').join('\n\n'),
      // Many variants → a buy-box taller than the gallery, so there is a real
      // pin window (the gallery stays put while the taller column scrolls).
      variants: [
        _v(1, ['https://x.test/a.png']),
        // Different image count to exercise the "no reflow on variant" case.
        _v(2, ['https://x.test/b.png', 'https://x.test/c.png'], color: 'Mavi'),
        for (var i = 3; i <= 8; i++)
          _v(i, ['https://x.test/$i.png'], color: 'Renk$i'),
      ],
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

double _galleryTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(PdpImagePager)).dy;

double _galleryHeight(WidgetTester tester) =>
    tester.getSize(find.byType(PdpImagePager)).height;

double _tabsTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(TabBar)).dy;

Future<void> _drag(WidgetTester tester, double dy) async {
  // Drag from a point over the buy-box column (right side, below the app bar)
  // so the gesture targets the page scroll view, not the horizontal thumb strip.
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

  // Desktop, but a narrower width so the gallery (capped, square) is shorter
  // than the many-variant buy-box — giving an observable pin window.
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
  await tester.pump(const Duration(milliseconds: 50)); // buy-box height measure
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('gallery pins on small scroll, releases past the column, re-pins',
      (tester) async {
    await _pump(tester);
    final pinnedY = _galleryTop(tester);

    // 1) Small forward scroll → still pinned (origin unchanged).
    await _drag(tester, -30);
    expect(
      _galleryTop(tester),
      closeTo(pinnedY, 1.0),
      reason: 'gallery should stay pinned for a small scroll',
    );

    // 2) Large forward scroll → past the two-column section → released
    //    (gallery has scrolled up, origin now above its pinned position) and
    //    the tab bar has crossed toward the top.
    await _drag(tester, -1200);
    expect(
      _galleryTop(tester),
      lessThan(pinnedY),
      reason: 'gallery should release and scroll up once the column ends',
    );
    expect(
      _tabsTop(tester),
      lessThan(pinnedY + 50),
      reason: 'tab bar should have crossed toward the viewport top',
    );

    // 3) Scroll back to the top → re-pins at the original origin.
    await _drag(tester, 1230);
    expect(
      _galleryTop(tester),
      closeTo(pinnedY, 1.0),
      reason: 'gallery should re-pin at its original position',
    );
  });

  testWidgets('gallery height is stable across a variant change', (tester) async {
    await _pump(tester);
    final h0 = _galleryHeight(tester);

    // Switch to the "Mavi / M" variant (carries a different image count).
    await tester.tap(find.textContaining('Mavi').first);
    await tester.pump();
    await tester.pump();

    expect(
      _galleryHeight(tester),
      closeTo(h0, 0.5),
      reason: 'variant change must not reflow the gallery column height',
    );
  });
}
