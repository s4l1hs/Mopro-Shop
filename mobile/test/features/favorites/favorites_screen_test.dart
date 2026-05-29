import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/favorites/favorites_screen.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/test_harness.dart';

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 1,
      brand: 'B',
      status: ProductSummaryStatusEnum.active,
      title: 'P$id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

/// Serves a /products/batch payload built from real ProductSummary.toJson().
class _BatchAdapter implements HttpClientAdapter {
  _BatchAdapter(this.products);
  final List<ProductSummary> products;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        jsonEncode({'data': products.map((p) => p.toJson()).toList()}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

int _gridColumns(WidgetTester tester) {
  final grid = tester.widget<GridView>(find.byType(GridView));
  final delegate =
      grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  return delegate.crossAxisCount;
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required Set<int> favIds,
}) async {
  // Untranslated cashback-chip strings inflate card height in tests; filter
  // that one render artifact.
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

  SharedPreferences.setMockInitialValues({
    if (favIds.isNotEmpty)
      'mopro_favorites': favIds.map((e) => e.toString()).toList(),
  });
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio()
    ..httpClientAdapter = _BatchAdapter([for (final id in favIds) _p(id)]);

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
}
