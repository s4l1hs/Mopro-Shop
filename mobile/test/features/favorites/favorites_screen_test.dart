import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/cart/application/cart_provider.dart';
import 'package:mopro/features/cart/data/cart_dto.dart';
import 'package:mopro/features/cart/data/cart_repository.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/favorites/favorites_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/test_harness.dart';

ProductSummary _p(int id, {int priceMinor = 20000, int? discountPct, bool freeShipping = false}) =>
    ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 1,
      brand: 'B',
      status: ProductSummaryStatusEnum.active,
      title: 'P$id',
      priceMinor: priceMinor,
      priceCurrency: 'TRY',
      discountPct: discountPct,
      originalPriceMinor:
          discountPct == null ? null : priceMinor * 100 ~/ (100 - discountPct),
      freeShipping: freeShipping,
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

Variant _v(int id, {required int stock}) => Variant(
      id: id,
      sku: 'SKU$id',
      priceMinor: 10000,
      priceCurrency: 'TRY',
      stock: stock,
      imageUrls: const [],
    );

Product _detail(int id, List<Variant> variants) => Product(
      id: id,
      sellerId: 1,
      sellerName: 'S',
      categoryId: 1,
      brand: 'B',
      status: ProductStatusEnum.active,
      title: 'P$id',
      description: '',
      variants: variants,
      attributes: const [],
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
      createdAt: DateTime.utc(2026),
    );

/// Serves POST /products/batch (from real ProductSummary.toJson()) and
/// GET /products/{id} (from real Product.toJson()) — the FAV-05 variant
/// resolution read path.
class _FakeApiAdapter implements HttpClientAdapter {
  _FakeApiAdapter(this.products, {this.details = const {}});
  final List<ProductSummary> products;
  final Map<int, Product> details;

  static ResponseBody _json(Object payload, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(payload),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/products/batch')) {
      return _json({'data': products.map((p) => p.toJson()).toList()});
    }
    final m = RegExp(r'/products/(\d+)$').firstMatch(options.path);
    if (m != null) {
      final detail = details[int.parse(m.group(1)!)];
      if (detail == null) return _json({'error': 'not_found'}, 404);
      return _json(detail.toJson());
    }
    return _json(const <String, dynamic>{});
  }

  @override
  void close({bool force = false}) {}
}

/// Records addItem calls; cart reads return an empty cart.
class _RecordingCartRepo implements CartRepository {
  final List<({int productId, int variantId, int qty})> added = [];

  @override
  Future<CartDto> getCart({String? coupon}) async => CartDto.empty();

  @override
  Future<CartDto> addItem({
    required int productId,
    required int variantId,
    required int qty,
  }) async {
    added.add((productId: productId, variantId: variantId, qty: qty));
    return CartDto.empty();
  }

  @override
  Future<CartDto> updateQty({required String lineId, required int qty}) async =>
      CartDto.empty();

  @override
  Future<void> removeLine({required String lineId}) async {}

  @override
  Future<void> clear() async {}
}

int _gridColumns(WidgetTester tester) {
  final grid = tester.widget<GridView>(find.byType(GridView));
  final delegate =
      grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  return delegate.crossAxisCount;
}

void _filterOverflow(WidgetTester tester) {
  // Untranslated cashback-chip strings inflate card height in tests; filter
  // that one render artifact.
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<void> _setView(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<Dio> _prepare(
  WidgetTester tester, {
  required List<ProductSummary> products,
  Map<int, Product> details = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    if (products.isNotEmpty)
      'mopro_favorites': products.map((p) => p.id.toString()).toList(),
  });
  return Dio()..httpClientAdapter = _FakeApiAdapter(products, details: details);
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required Set<int> favIds,
}) async {
  _filterOverflow(tester);
  await _setView(tester, size);
  final dio =
      await _prepare(tester, products: [for (final id in favIds) _p(id)]);
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dioProvider.overrideWithValue(dio),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const FavoritesScreen(),
      ),
    ),
  );
  await tester.pump(); // resolve the FutureProvider
  await tester.pump();
  // Flush Dio's one-shot scheduling timer so it doesn't outlive disposal.
  await tester.pump(const Duration(milliseconds: 50));
}

/// FAV-05 harness: favorites under a GoRouter (the multi-variant path pushes
/// the PDP route) with a recording cart repo.
Future<_RecordingCartRepo> _pumpWithRouter(
  WidgetTester tester, {
  required List<ProductSummary> products,
  required Map<int, Product> details,
}) async {
  _filterOverflow(tester);
  await _setView(tester, const Size(375, 900));
  final dio = await _prepare(tester, products: products, details: details);
  final prefs = await SharedPreferences.getInstance();
  final cartRepo = _RecordingCartRepo();

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const FavoritesScreen()),
      GoRoute(
        path: '/products/:id',
        builder: (_, s) =>
            Scaffold(body: Text('pdp-${s.pathParameters['id']}')),
      ),
      GoRoute(path: '/cart', builder: (_, __) => const Scaffold(body: Text('cart'))),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dioProvider.overrideWithValue(dio),
        cartRepositoryProvider.overrideWithValue(cartRepo),
      ],
      child: MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return cartRepo;
}

Future<void> _tapAtc(WidgetTester tester) async {
  await tester.tap(find.text('product.add_to_cart').first);
  await tester.pump(); // start the resolution request
  await tester.pump(const Duration(milliseconds: 50)); // adapter responds
  await tester.pump(); // snackbar enters
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('empty favorites render the empty state, no grid', (tester) async {
    await _pump(tester, size: const Size(1440, 900), favIds: const {});
    expect(find.text('favorites.empty_title'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('populated grid columns adapt: 2 mobile', (tester) async {
    await _pump(tester, size: const Size(375, 900), favIds: const {1, 2, 3});
    expect(find.byType(ProductCard), findsWidgets);
    expect(_gridColumns(tester), 2);
  });

  testWidgets('populated grid columns adapt: 4 tablet', (tester) async {
    await _pump(tester, size: const Size(768, 1100), favIds: const {1, 2, 3});
    expect(_gridColumns(tester), 4);
  });

  testWidgets('populated grid columns adapt: 5 desktop', (tester) async {
    await _pump(tester, size: const Size(1440, 1100), favIds: const {1, 2, 3});
    expect(_gridColumns(tester), 5);
  });

  // ── FAV-05: add-to-cart from the favorites card ─────────────────────────────

  testWidgets('FAV-05: every favorites card carries an add-to-cart button',
      (tester) async {
    await _pump(tester, size: const Size(375, 900), favIds: const {1, 2});
    expect(find.text('product.add_to_cart'), findsNWidgets(2));
  });

  testWidgets('FAV-05: single in-stock variant adds directly to the cart',
      (tester) async {
    final cartRepo = await _pumpWithRouter(
      tester,
      products: [_p(1)],
      details: {
        1: _detail(1, [_v(11, stock: 5)]),
      },
    );
    await _tapAtc(tester);
    expect(cartRepo.added, [(productId: 1, variantId: 11, qty: 1)]);
    expect(find.text('cart.added_to_cart'), findsOneWidget);
  });

  testWidgets(
      'FAV-05: multi-variant picks the only in-stock one (forced choice)',
      (tester) async {
    final cartRepo = await _pumpWithRouter(
      tester,
      products: [_p(1)],
      details: {
        1: _detail(1, [_v(11, stock: 0), _v(12, stock: 3)]),
      },
    );
    await _tapAtc(tester);
    expect(cartRepo.added, [(productId: 1, variantId: 12, qty: 1)]);
  });

  testWidgets('FAV-05: all variants out of stock → OOS snackbar, no add',
      (tester) async {
    final cartRepo = await _pumpWithRouter(
      tester,
      products: [_p(1)],
      details: {
        1: _detail(1, [_v(11, stock: 0), _v(12, stock: 0)]),
      },
    );
    await _tapAtc(tester);
    expect(cartRepo.added, isEmpty);
    expect(find.text('favorites.out_of_stock'), findsOneWidget);
  });

  testWidgets(
      'FAV-05: several in-stock variants route to the PDP for selection',
      (tester) async {
    final cartRepo = await _pumpWithRouter(
      tester,
      products: [_p(1)],
      details: {
        1: _detail(1, [_v(11, stock: 5), _v(12, stock: 3)]),
      },
    );
    await _tapAtc(tester);
    expect(cartRepo.added, isEmpty);
    expect(find.text('favorites.select_options'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('pdp-1'), findsOneWidget);
  });

  testWidgets('FAV-05: resolution failure shows the add-failed snackbar',
      (tester) async {
    final cartRepo = await _pumpWithRouter(
      tester,
      products: [_p(1)],
      details: const {}, // GET /products/1 → 404
    );
    await _tapAtc(tester);
    expect(cartRepo.added, isEmpty);
    expect(find.text('cart.add_failed'), findsOneWidget);
  });

  // ── FAV-06: client-side sort/filter ─────────────────────────────────────────

  /// Visible card titles in grid (paint) order.
  List<String> titlesOf(WidgetTester tester) => [
        for (final w in tester.widgetList<ProductCard>(find.byType(ProductCard)))
          w.product.title,
      ];

  Future<void> selectSort(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('FAV-06: price sort reorders the grid both ways', (tester) async {
    await _pumpWithRouter(
      tester,
      products: [
        _p(1, priceMinor: 30000),
        _p(2, priceMinor: 10000),
        _p(3, priceMinor: 20000),
      ],
      details: const {},
    );
    expect(titlesOf(tester).take(2), ['P1', 'P2']); // fetch order

    await selectSort(tester, 'catalog.sort_price_asc');
    expect(titlesOf(tester).first, 'P2');

    await selectSort(tester, 'catalog.sort_price_desc');
    expect(titlesOf(tester).first, 'P1');
  });

  testWidgets('FAV-06: discount sort puts the deepest discount first',
      (tester) async {
    await _pumpWithRouter(
      tester,
      products: [_p(1), _p(2, discountPct: 10), _p(3, discountPct: 40)],
      details: const {},
    );
    await selectSort(tester, 'favorites.sort_discount');
    expect(titlesOf(tester).take(2), ['P3', 'P2']);
  });

  testWidgets('FAV-06: discounted + free-shipping chips prune the grid',
      (tester) async {
    await _pumpWithRouter(
      tester,
      products: [
        _p(1),
        _p(2, discountPct: 10),
        _p(3, freeShipping: true),
        _p(4, discountPct: 20, freeShipping: true),
      ],
      details: const {},
    );
    expect(find.byType(ProductCard), findsNWidgets(4));

    await tester.tap(find.widgetWithText(FilterChip, 'favorites.filter_discounted'));
    await tester.pumpAndSettle();
    expect(titlesOf(tester), ['P2', 'P4']);

    await tester.ensureVisible(
      find.widgetWithText(FilterChip, 'plp.free_shipping'),
    );
    await tester.tap(find.widgetWithText(FilterChip, 'plp.free_shipping'));
    await tester.pumpAndSettle();
    expect(titlesOf(tester), ['P4']);

    // Deselect both → everything back.
    await tester.tap(find.widgetWithText(FilterChip, 'favorites.filter_discounted'));
    await tester.ensureVisible(
      find.widgetWithText(FilterChip, 'plp.free_shipping'),
    );
    await tester.tap(find.widgetWithText(FilterChip, 'plp.free_shipping'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductCard), findsNWidgets(4));
  });

  testWidgets('FAV-06: filters that prune everything show the filter-empty hint',
      (tester) async {
    await _pumpWithRouter(
      tester,
      products: [_p(1), _p(2)],
      details: const {},
    );
    await tester.tap(find.widgetWithText(FilterChip, 'favorites.filter_discounted'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductCard), findsNothing);
    expect(find.text('favorites.filter_empty'), findsOneWidget);
    // The true empty state is NOT shown — favorites are intact.
    expect(find.text('favorites.empty_title'), findsNothing);
  });
}
