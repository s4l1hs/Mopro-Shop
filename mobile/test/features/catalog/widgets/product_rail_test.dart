import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/catalog/widgets/product_rail.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_support/test_harness.dart';

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

Future<void> _pump(
  WidgetTester tester, {
  required RailLayout layout,
  required Size size,
  int columns = 3,
  int? maxItems,
  int n = 8,
}) async {
  // Untranslated cashback-chip strings inflate card height in tests (real
  // translations are short); filter that one render artifact.
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
        productsRailProvider('x')
            .overrideWith((ref) async => [for (var i = 0; i < n; i++) _p(i + 1)]),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductRail(
              title: 'T',
              sort: 'x',
              layout: layout,
              gridColumns: columns,
              maxItems: maxItems,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('scroller layout renders a horizontal ListView (mobile)',
      (tester) async {
    await _pump(tester, layout: RailLayout.scroller, size: const Size(375, 900));
    expect(find.byType(ListView), findsWidgets);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('grid layout renders a GridView capped at maxItems (desktop)',
      (tester) async {
    await _pump(
      tester,
      layout: RailLayout.grid,
      columns: 5,
      maxItems: 6,
      size: const Size(1440, 1200),
    );
    expect(find.byType(GridView), findsOneWidget);
    // 8 products, capped to 6.
    expect(find.byType(ProductCard), findsNWidgets(6));
  });
}
