import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/anchored_overlay_panel.dart';
import 'package:mopro/design/responsive/pointer_kind.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_bar.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_focus_ring.dart';
import 'package:mopro_api/mopro_api.dart';

import '../_support/test_harness.dart';

// Erkek(1): Giyim(10)>[T-shirt,Jean], Ayakkabı(11)>[Sneaker]   (no promo)
// Kadın(2)+promo: Çanta(20)>[Clutch]                            (3+1)
// Çocuk(3): Oyuncak(30)>[Lego]
final _promo = CategoryPromoSlot(
  imageUrl: 'https://example.test/promo.png',
  title: 'Yaz İndirimi',
  deepLink: '/categories/2?campaign=yaz',
);

Category _cat(int id, String name, {int? parentId, CategoryPromoSlot? promo}) =>
    Category(
      id: id,
      name: name,
      slug: name.toLowerCase(),
      parentId: parentId,
      commissionPctBps: 1000,
      promoSlot: promo,
    );

List<Category> _cats() => [
      _cat(1, 'Erkek'),
      _cat(2, 'Kadın', promo: _promo),
      _cat(3, 'Çocuk'),
      _cat(10, 'Giyim', parentId: 1),
      _cat(11, 'Ayakkabı', parentId: 1),
      _cat(20, 'Çanta', parentId: 2),
      _cat(30, 'Oyuncak', parentId: 3),
      _cat(100, 'T-shirt', parentId: 10),
      _cat(101, 'Jean', parentId: 10),
      _cat(110, 'Sneaker', parentId: 11),
      _cat(200, 'Clutch', parentId: 20),
      _cat(300, 'Lego', parentId: 30),
    ];

class _SeededCategoriesNotifier extends CategoriesNotifier {
  _SeededCategoriesNotifier(this._seed);
  final List<Category> _seed;
  @override
  CategoriesState build() => CategoriesState(categories: AsyncData(_seed));
}

// A focusable that stands in for "the next page focusable" (the WebHeader icon
// stack / page body in the real app), so Tab-past-last has somewhere to yield.
final _nextFocusNode = FocusNode(debugLabel: 'next-page-focusable');

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: Column(
              children: [
                const MegaMenuBar(),
                TextButton(
                  focusNode: _nextFocusNode,
                  onPressed: () {},
                  child: const Text('NEXT'),
                ),
                const Expanded(child: Center(child: Text('HOME'))),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/categories/:id',
          builder: (_, s) =>
              Scaffold(body: Center(child: Text('PLP_${s.pathParameters['id']}'))),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        categoriesProvider.overrideWith(() => _SeededCategoriesNotifier(_cats())),
      ],
      child: MaterialApp.router(theme: buildLightTheme(), routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

bool _ringShownOn(WidgetTester tester, String text) {
  final f =
      find.ancestor(of: find.text(text), matching: find.byType(MegaMenuFocusRing));
  if (f.evaluate().isEmpty) return false;
  return tester.widget<MegaMenuFocusRing>(f.first).show;
}

void main() {
  setUpAll(initTestEnv);
  setUp(debugResetAnchoredOverlayPanelRegistry);
  tearDown(PointerKindObserver.debugReset);

  // ── Flow I — pointer-device mega menu ───────────────────────────────────
  testWidgets('Flow I: hover opens 4-col, move to promo cat opens 3+1, leaf routes',
      (tester) async {
    await _pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    addTearDown(mouse.removePointer);

    // Hover Erkek → 4-column panel (no promo CTA).
    await mouse.moveTo(tester.getCenter(find.text('Erkek')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('Giyim'), findsOneWidget);
    expect(find.text('mega_menu.promo.cta'), findsNothing);

    // Move to Kadın (has promoSlot) → A closes via exclusivity, B opens 3+1.
    await mouse.moveTo(tester.getCenter(find.text('Kadın')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('Giyim'), findsNothing);
    expect(find.text('Çanta'), findsOneWidget);
    expect(find.text('mega_menu.promo.cta'), findsOneWidget);

    // Click a leaf → routes to its PLP and the panel closes on route change.
    await tester.tap(find.text('Clutch'));
    await tester.pumpAndSettle();
    expect(find.text('PLP_200'), findsOneWidget);
    expect(find.text('Çanta'), findsNothing);
  });

  // ── Flow J — keyboard mega menu ─────────────────────────────────────────
  testWidgets('Flow J: Tab in, Arrow Right x2, Arrow Down opens + focuses leaf, '
      'Tab-past-last closes, re-open + Escape', (tester) async {
    await _pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // → Erkek
    await tester.pump(const Duration(milliseconds: 50));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // → Kadın
    await tester.pump(const Duration(milliseconds: 50));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // → Çocuk (index 2)
    await tester.pump(const Duration(milliseconds: 50));
    expect(_ringShownOn(tester, 'Çocuk'), isTrue); // active item is index 2

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // open Çocuk panel
    await tester.pump();
    await tester.pump();
    expect(find.text('Oyuncak'), findsOneWidget); // Çocuk's subcat
    expect(_ringShownOn(tester, 'Lego'), isTrue); // first leaf focused

    // Çocuk focusables: Oyuncak header, Lego. From Lego: Tab → trailing
    // sentinel → panel closes AND focus yields to the next page focusable.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.text('Oyuncak'), findsNothing); // panel closed
    expect(_nextFocusNode.hasFocus, isTrue); // yielded onward

    // Tab back into the bar item, Arrow Down to re-open, Escape to close.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(find.text('Oyuncak'), findsOneWidget); // re-opened
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Oyuncak'), findsNothing); // Escape closed it
  });

  // ── Flow K — touch mega menu (simulated) ────────────────────────────────
  testWidgets('Flow K: tap opens, tap same closes, tap other opens, leaf routes',
      (tester) async {
    PointerKindObserver.lastKind.value = LastPointerKind.touch;
    await _pump(tester);

    // Tap Erkek → opens (no navigation).
    await tester.tap(find.text('Erkek'));
    await tester.pumpAndSettle();
    expect(find.text('Giyim'), findsOneWidget);
    expect(find.text('PLP_1'), findsNothing);

    // Tap the same item again → closes.
    await tester.tap(find.text('Erkek'));
    await tester.pumpAndSettle();
    expect(find.text('Giyim'), findsNothing);

    // Tap a different item → its panel opens.
    await tester.tap(find.text('Kadın'));
    await tester.pumpAndSettle();
    expect(find.text('Çanta'), findsOneWidget);

    // Tap a leaf → routes to PLP.
    await tester.tap(find.text('Clutch'));
    await tester.pumpAndSettle();
    expect(find.text('PLP_200'), findsOneWidget);
  });
}
