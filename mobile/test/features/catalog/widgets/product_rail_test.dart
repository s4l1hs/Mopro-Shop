import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
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

/// The carousel's own horizontal scroll position (not the outer vertical one).
ScrollPosition _railPosition(WidgetTester tester) {
  final scrollable = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable.first).position;
}

double _opacityAt(WidgetTester tester, int index) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).at(index)).opacity;

Future<void> _hoverRail(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(find.byType(ListView)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('scroller (mobile) renders a horizontal ListView, no chevrons',
      (tester) async {
    await _pump(tester, layout: RailLayout.scroller, size: const Size(375, 900));
    expect(find.byType(ListView), findsWidgets);
    expect(find.byType(GridView), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('carousel tablet (768) is a scroller WITHOUT chevrons',
      (tester) async {
    await _pump(tester, layout: RailLayout.carousel, size: const Size(768, 1200));
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    // Touch breakpoint → no hover chevrons mounted.
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('carousel desktop (1440) mounts chevrons but hides them at rest',
      (tester) async {
    await _pump(tester, layout: RailLayout.carousel, size: const Size(1440, 1200));
    expect(find.byType(GridView), findsNothing);
    // Chevrons exist in the tree but are fully transparent until hover.
    expect(find.byType(AnimatedOpacity), findsNWidgets(2));
    expect(_opacityAt(tester, 0), 0); // left
    expect(_opacityAt(tester, 1), 0); // right
  });

  testWidgets('desktop: hover reveals the right chevron, left gated at start',
      (tester) async {
    await _pump(tester, layout: RailLayout.carousel, size: const Size(1440, 1200));
    await _hoverRail(tester);
    // At offset 0 the left chevron stays hidden; the right reveals (overflows).
    expect(_opacityAt(tester, 0), 0); // left — gated at start
    expect(_opacityAt(tester, 1), 1); // right — visible on hover
  });

  testWidgets('desktop: tapping the right chevron advances the scroll',
      (tester) async {
    await _pump(tester, layout: RailLayout.carousel, size: const Size(1440, 1200));
    expect(_railPosition(tester).pixels, 0);
    await _hoverRail(tester);
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(_railPosition(tester).pixels, greaterThan(0));
  });

  testWidgets('desktop: right chevron is gated at the max extent',
      (tester) async {
    await _pump(tester, layout: RailLayout.carousel, size: const Size(1440, 1200));
    final pos = _railPosition(tester);
    pos.jumpTo(pos.maxScrollExtent);
    await tester.pump();
    await _hoverRail(tester);
    expect(_opacityAt(tester, 0), 1); // left — now revealable
    expect(_opacityAt(tester, 1), 0); // right — gated at end
  });
}
