import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/home/providers/flash_deals_provider.dart';
import 'package:mopro/features/home/widgets/flash_deals_rail.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/test_harness.dart';

final _now = DateTime.utc(2026, 6, 1, 12);

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 1,
      brand: 'B',
      status: ProductSummaryStatusEnum.active,
      title: 'P$id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      flashPriceMinor: 9999,
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

FlashDealsCollection _col({Duration ttl = const Duration(minutes: 15), int n = 8}) =>
    FlashDealsCollection(
      id: 1,
      title: 'Bugünün Fırsatları',
      endsAt: _now.add(ttl),
      products: [for (var i = 0; i < n; i++) _p(i + 1)],
    );

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) =>
              const Scaffold(body: SingleChildScrollView(child: FlashDealsRail())),
        ),
        GoRoute(
          path: '/products/:id',
          builder: (_, s) =>
              Scaffold(body: Center(child: Text('PDP_${s.pathParameters['id']}'))),
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required FlashDealsCollection? col,
  Size size = const Size(390, 900),
}) async {
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
        flashDealsProvider.overrideWith((ref) async => col),
      ],
      child: MaterialApp.router(theme: buildLightTheme(), routerConfig: _router()),
    ),
  );
  // NOTE: never pumpAndSettle — the 1s countdown ticker never settles.
  await tester.pump(); // resolve the FutureProvider
  await tester.pump();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('header shows the title + HH:MM:SS countdown; body renders cards',
      (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _pump(tester, col: _col());
      expect(find.text('Bugünün Fırsatları'), findsOneWidget);
      expect(find.text('00:15:00'), findsOneWidget);
      expect(find.byType(ProductCard), findsWidgets);
    });
  });

  testWidgets('at zero the header shows the ended state and the body collapses',
      (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _pump(tester, col: _col(ttl: const Duration(seconds: -1)));
      expect(find.text('home.flash_deals_ended'), findsOneWidget);
      expect(find.text('00:15:00'), findsNothing);
      expect(find.byType(ProductCard), findsNothing);
    });
  });

  testWidgets('renders nothing when there is no active collection',
      (tester) async {
    await _pump(tester, col: null);
    expect(find.byType(ProductCard), findsNothing);
    expect(find.text('Bugünün Fırsatları'), findsNothing);
  });

  testWidgets('mobile uses a horizontal scroller', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _pump(tester, col: _col());
      expect(find.byType(ListView), findsWidgets);
    });
  });

  testWidgets('desktop uses a grid', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _pump(tester, col: _col(), size: const Size(1440, 1000));
      expect(find.byType(GridView), findsOneWidget);
    });
  });

  testWidgets('tapping a card routes to the PDP', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _pump(tester, col: _col(n: 3));
      await tester.tap(find.byType(ProductCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('PDP_1'), findsOneWidget);
    });
  });
}
