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

import '../../../_support/test_harness.dart';

Category _cat(int id, String name, {int? parentId}) => Category(
      id: id,
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      parentId: parentId,
      commissionPctBps: 1000,
    );

// Erkek(1) > Giyim(10)>[T-shirt(100),Jean(101)], Ayakkabı(11)>[Sneaker(110)]
// Kadın(2) > Çanta(20)
List<Category> _sample() => [
      _cat(1, 'Erkek'),
      _cat(2, 'Kadın'),
      _cat(10, 'Giyim', parentId: 1),
      _cat(11, 'Ayakkabı', parentId: 1),
      _cat(20, 'Çanta', parentId: 2),
      _cat(100, 'T-shirt', parentId: 10),
      _cat(101, 'Jean', parentId: 10),
      _cat(110, 'Sneaker', parentId: 11),
    ];

class _SeededCategoriesNotifier extends CategoriesNotifier {
  _SeededCategoriesNotifier(this._seed);
  final List<Category> _seed;
  @override
  CategoriesState build() => CategoriesState(categories: AsyncData(_seed));
}

GoRouter _stubRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            body: Column(
              children: [
                MegaMenuBar(),
                Expanded(child: Center(child: Text('HOME'))),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/categories/:id',
          builder: (_, state) =>
              Scaffold(body: Center(child: Text('PLP_${state.pathParameters['id']}'))),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        categoriesProvider
            .overrideWith(() => _SeededCategoriesNotifier(_sample())),
      ],
      child: MaterialApp.router(
        theme: buildLightTheme(),
        routerConfig: _stubRouter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
}

Future<void> _shiftTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey k) async {
  await tester.sendKeyEvent(k);
  await tester.pump();
}

bool _ringShownOn(WidgetTester tester, String text) {
  final ring = tester.widget<MegaMenuFocusRing>(
    find
        .ancestor(of: find.text(text), matching: find.byType(MegaMenuFocusRing))
        .first,
  );
  return ring.show;
}

bool _anyRingShown(WidgetTester tester) => tester
    .widgetList<MegaMenuFocusRing>(find.byType(MegaMenuFocusRing))
    .any((r) => r.show);

void main() {
  setUpAll(initTestEnv);
  setUp(debugResetAnchoredOverlayPanelRegistry);
  tearDown(PointerKindObserver.debugReset);

  group('focus ring', () {
    testWidgets('shows on keyboard focus, hidden after a pointer tap',
        (tester) async {
      await _pump(tester);
      await _tab(tester); // focus first bar item via keyboard
      expect(_anyRingShown(tester), isTrue);

      // A touch tap switches the highlight mode to touch → ring hides.
      await tester.tap(find.text('HOME'));
      await tester.pump();
      expect(_anyRingShown(tester), isFalse);
    });
  });

  group('bar arrow navigation', () {
    testWidgets('Arrow Right/Left move the active item (panel follows)',
        (tester) async {
      await _pump(tester);
      await _tab(tester); // Erkek focused
      await tester.pump(const Duration(milliseconds: 100)); // panel opens
      await tester.pump();
      expect(find.text('Giyim'), findsOneWidget); // Erkek's panel

      await _key(tester, LogicalKeyboardKey.arrowRight); // → Kadın
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Çanta'), findsOneWidget); // Kadın's panel
      expect(find.text('Giyim'), findsNothing); // exclusivity closed Erkek's

      await _key(tester, LogicalKeyboardKey.arrowLeft); // ← Erkek
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Giyim'), findsOneWidget);
    });
  });

  group('bar Arrow Down', () {
    testWidgets('opens the panel and focuses the first leaf of column 1',
        (tester) async {
      await _pump(tester);
      await _tab(tester); // Erkek focused
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump(); // mount panel
      await tester.pump(); // post-frame focus request
      expect(find.text('Giyim'), findsOneWidget);
      // First leaf of first column (Giyim) is T-shirt → it carries the ring.
      expect(_ringShownOn(tester, 'T-shirt'), isTrue);
    });
  });

  group('bar Enter/Space', () {
    testWidgets('Enter routes to the PLP on pointer-class devices',
        (tester) async {
      await _pump(tester);
      await _tab(tester);
      await _key(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('PLP_1'), findsOneWidget);
    });

    testWidgets('Space routes to the PLP on pointer-class devices',
        (tester) async {
      await _pump(tester);
      await _tab(tester);
      await _key(tester, LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('PLP_1'), findsOneWidget);
    });

    testWidgets('Enter opens the panel (no route) on touch-class devices',
        (tester) async {
      PointerKindObserver.lastKind.value = LastPointerKind.touch;
      await _pump(tester);
      await _tab(tester);
      await _key(tester, LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(find.text('PLP_1'), findsNothing);
      expect(find.text('Giyim'), findsOneWidget);
    });
  });

  group('Escape', () {
    testWidgets('closes the open panel', (tester) async {
      await _pump(tester);
      await _tab(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Giyim'), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Giyim'), findsNothing);
    });
  });

  group('panel column-major traversal', () {
    testWidgets('Tab from first leaf goes down the column (not across)',
        (tester) async {
      await _pump(tester);
      await _tab(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(_ringShownOn(tester, 'T-shirt'), isTrue);

      await _tab(tester); // next in column-major order
      expect(_ringShownOn(tester, 'Jean'), isTrue); // same column (Giyim)
      expect(_ringShownOn(tester, 'Ayakkabı'), isFalse); // not the next column
    });
  });

  group('panel Tab sentinels', () {
    testWidgets('Shift+Tab before the first focusable closes the panel',
        (tester) async {
      await _pump(tester);
      await _tab(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(find.text('Giyim'), findsOneWidget);
      await _shiftTab(tester); // T-shirt → Giyim header
      await _shiftTab(tester); // header → leading sentinel → close
      await tester.pumpAndSettle();
      expect(find.text('Giyim'), findsNothing);
    });

    testWidgets('Tab past the last focusable closes the panel', (tester) async {
      await _pump(tester);
      await _tab(tester);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      // Order from T-shirt: Jean, Ayakkabı header, Sneaker, then sentinel.
      await _tab(tester); // Jean
      await _tab(tester); // Ayakkabı header
      await _tab(tester); // Sneaker
      await _tab(tester); // trailing sentinel → close
      await tester.pumpAndSettle();
      expect(find.text('Giyim'), findsNothing);
    });
  });

  group('semantics', () {
    testWidgets('bar + items carry semantic labels and hints', (tester) async {
      await _pump(tester);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Top-level categories'), findsOneWidget);
      // A bar item is a button labeled with its category name…
      final erkek = tester.getSemantics(find.text('Erkek'));
      expect(erkek.label, contains('Erkek'));
      // …and items with children expose the submenu hint. Tests don't load the
      // bundle, so .tr() returns the key (mega_menu.submenu_hint → "Submenü açmak
      // için Aşağı ok" in tr-TR.json, which contains the Arrow-Down cue).
      expect(erkek.hint, contains('mega_menu.submenu_hint'));
      handle.dispose();
    });

    testWidgets('open panel exposes submenu + leaf button labels',
        (tester) async {
      await _pump(tester);
      await _tab(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Category submenu for Erkek'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('T-shirt'), findsWidgets);
      handle.dispose();
    });
  });
}
