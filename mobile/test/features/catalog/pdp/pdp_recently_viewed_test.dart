import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/api/client.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/screens/product_detail_screen.dart';
import 'package:mopro/features/catalog/widgets/product_list_rail.dart';
import 'package:mopro/features/home/recently_viewed_provider.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_support/test_harness.dart';

// PD-10: the PDP mounts the recently-viewed rail (read-only ProductListRail over
// recentlyViewedProvider) and filters the product being viewed out of it.

Variant _v(int id) => Variant(
      id: id,
      sku: 'SKU$id',
      color: 'Kırmızı',
      size: 'M',
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
      attributes: const [],
      title: 'Test Ürünü',
      description: 'Açıklama',
      variants: [_v(1)],
      cashbackPreview:
          CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
      createdAt: DateTime.utc(2026),
    );

ProductSummary _summary(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 5,
      brand: 'Acme',
      status: ProductSummaryStatusEnum.active,
      title: 'Geçmiş Ürün $id',
      priceMinor: 9900,
      priceCurrency: 'TRY',
      cashbackPreview:
          CashbackPreview(monthlyCoinMinor: 80, currency: 'TRY_COIN'),
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

/// Fixed-state stand-in for the auth/consent-gated home notifier.
class _FixedRecentlyViewed extends RecentlyViewedNotifier {
  _FixedRecentlyViewed(this._items);

  final List<ProductSummary> _items;

  @override
  AsyncValue<List<ProductSummary>> build() => AsyncValue.data(_items);
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required List<ProductSummary> recentlyViewed,
}) async {
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
        recentlyViewedProvider
            .overrideWith(() => _FixedRecentlyViewed(recentlyViewed)),
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

  testWidgets('wide PDP renders the recently-viewed rail, current product excluded',
      (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 900),
      // Includes the product being viewed (123) → must be filtered out.
      recentlyViewed: [_summary(7), _summary(123), _summary(8)],
    );

    expect(find.byType(ProductListRail), findsWidgets);
    expect(find.text('Geçmiş Ürün 7'), findsOneWidget);
    expect(find.text('Geçmiş Ürün 8'), findsOneWidget);
    expect(
      find.text('Geçmiş Ürün 123'),
      findsNothing,
      reason: 'the product being viewed must not echo into its own rail',
    );
  });

  testWidgets('rail renders zero space when recently-viewed is empty',
      (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 900),
      recentlyViewed: const [],
    );
    expect(find.textContaining('Geçmiş Ürün'), findsNothing);
  });

  testWidgets(
      'rail hides when the only entry is the product being viewed',
      (tester) async {
    await _pump(
      tester,
      size: const Size(1280, 900),
      recentlyViewed: [_summary(123)],
    );
    expect(find.textContaining('Geçmiş Ürün'), findsNothing);
  });
}
