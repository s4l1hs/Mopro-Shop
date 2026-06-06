import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/responsive/pointer_kind.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_line_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';
import 'package:mopro/features/cart/data/cart_totals_dto.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_image_pager.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

// ── Flow P — desktop PDP composition, hover-zoom, variant, cart, sticky ──────────

class _FakeCartRepo implements CartRepository {
  CartDto _cart = const CartDto(
    id: 'c-1',
    userId: 1,
    lines: [],
    totalsBySeller: [],
    grandTotalMinor: 0,
    kdvIncludedMinor: 0,
  );

  @override
  Future<CartDto> getCart() async => _cart;

  @override
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  }) async {
    final line = CartLineDto(
      id: 'line-1',
      productId: productId,
      variantId: variantId,
      sellerId: 10,
      title: 'Test',
      priceMinor: 9900,
      qty: qty,
    );
    return _cart = CartDto(
      id: 'c-1',
      userId: 1,
      lines: [line],
      totalsBySeller: [
        SellerTotalDto(
          sellerId: 10,
          itemsMinor: line.lineTotalMinor,
          shippingMinor: 0,
          totalMinor: line.lineTotalMinor,
        ),
      ],
      grandTotalMinor: line.lineTotalMinor,
      kdvIncludedMinor: 0,
    );
  }

  @override
  Future<CartDto> updateQty({required String lineId, required int qty}) async =>
      _cart;

  @override
  Future<void> removeLine({required String lineId}) async {}

  @override
  Future<void> clear() async {}
}

Variant _v(int id, {required String color, int price = 12900}) => Variant(
      id: id,
      sku: 'SKU$id',
      color: color,
      size: 'M',
      priceMinor: price,
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
      title: 'Test Ürünü',
      // Long below-fold content so the page can scroll past the pin window.
      description: List.filled(60, 'Lorem ipsum dolor sit amet.').join('\n\n'),
      variants: [
        _v(1, color: 'Kırmızı'),
        _v(2, color: 'Mavi', price: 9900),
        // Pad the buy-box taller than the gallery so a pin window exists.
        for (var i = 3; i <= 12; i++) _v(i, color: 'Renk$i'),
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

void main() {
  setUpAll(initTestEnv);
  tearDown(PointerKindObserver.debugReset);

  testWidgets('Flow P: composition, hover-zoom, variant, cart, sticky release',
      (tester) async {
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PointerKindObserver.lastKind.value = LastPointerKind.mouse;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          catalogApiProvider.overrideWithValue(_FakeCatalogApi()),
          cartRepositoryProvider.overrideWithValue(_FakeCartRepo()),
        ],
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const ProductDetailScreen(productId: 123),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final container =
        ProviderScope.containerOf(tester.element(find.byType(ProductDetailScreen)));

    // 3) Two-column composition present.
    expect(find.byType(PdpImagePager), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'product.add_to_cart'), findsOneWidget);

    // 4) Mouse hover over the gallery → zoom lens visible.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(PdpImagePager)));
    await tester.pump();
    expect(find.byKey(PdpImagePager.zoomOverlayKey), findsOneWidget);

    // 5) Move the cursor out → lens disappears.
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(find.byKey(PdpImagePager.zoomOverlayKey), findsNothing);

    // 6) Select the "Mavi" variant → it becomes selected.
    await tester.tap(find.textContaining('Mavi').first);
    await tester.pump();
    final mavi = tester.widget<FilterChip>(
      find.ancestor(
        of: find.textContaining('Mavi'),
        matching: find.byType(FilterChip),
      ),
    );
    expect(mavi.selected, isTrue);

    // 7) Add to cart → cart count increments.
    expect(container.read(cartCountProvider), 0);
    await tester.tap(find.widgetWithText(FilledButton, 'product.add_to_cart'));
    await tester.pump();
    await tester.pump();
    expect(container.read(cartCountProvider), 1);

    // 8) Scroll far down → the sticky gallery releases (origin moves up).
    final pinnedY = tester.getTopLeft(find.byType(PdpImagePager)).dy;
    await tester.dragFrom(const Offset(1100, 300), const Offset(0, -1500));
    await tester.pump();
    await tester.pump();
    expect(
      tester.getTopLeft(find.byType(PdpImagePager)).dy,
      lessThan(pinnedY),
      reason: 'gallery should release once the column scrolls past',
    );
  });
}
