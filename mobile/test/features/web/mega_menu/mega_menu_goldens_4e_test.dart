import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_bar.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_panel.dart';
import 'package:mopro_api/mopro_api.dart';

import '../../../_support/test_harness.dart';

// NOTE: baselines for these goldens are generated on Linux/CI via the
// `golden-rebaseline` workflow (`make update-goldens`); see CONTRIBUTING.md.
// The platform guard (test/_support/golden_platform.dart) fails these on
// non-CI platforms with a remediation message rather than a pixel diff.

Category _cat(int id, String name, {int? parentId}) => Category(
      id: id,
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      parentId: parentId,
      commissionPctBps: 1000,
    );

List<Category> _cats() => [
      _cat(1, 'Erkek'),
      _cat(2, 'Kadın'),
      _cat(3, 'Çocuk'),
      _cat(10, 'Giyim', parentId: 1),
      _cat(11, 'Ayakkabı', parentId: 1),
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

CategoryNode _node(Category c, [List<CategoryNode>? children]) =>
    CategoryNode(category: c, children: children);

CategoryNode _panelModel() {
  final l1 = _node(_cat(100, 'T-shirt', parentId: 10));
  final l2 = _node(_cat(101, 'Jean', parentId: 10));
  final l3 = _node(_cat(110, 'Sneaker', parentId: 11));
  final sub1 = _node(_cat(10, 'Giyim', parentId: 1), [l1, l2]);
  final sub2 = _node(_cat(11, 'Ayakkabı', parentId: 1), [l3]);
  return _node(_cat(1, 'Erkek'), [sub1, sub2]);
}

GoRouter _barRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: MegaMenuBar()),
        ),
      ],
    );

Future<void> _pumpBar(WidgetTester tester, Size size, Brightness b) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        categoriesProvider.overrideWith(() => _SeededCategoriesNotifier(_cats())),
      ],
      child: MaterialApp.router(
        theme: b == Brightness.dark ? buildDarkTheme() : buildLightTheme(),
        routerConfig: _barRouter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPanel(WidgetTester tester, Size size, Brightness b) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: b == Brightness.dark ? buildDarkTheme() : buildLightTheme(),
      home: Scaffold(
        body: MegaMenuPanel(active: _panelModel(), onDismiss: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('bar collapsed at 1024 light', (tester) async {
    await _pumpBar(tester, const Size(1024, 600), Brightness.light);
    await expectLater(
      find.byType(MegaMenuBar),
      matchesGoldenFile('goldens/mega_menu_bar_collapsed_1024_light.png'),
    );
  });

  testWidgets('bar collapsed at 1024 dark', (tester) async {
    await _pumpBar(tester, const Size(1024, 600), Brightness.dark);
    await expectLater(
      find.byType(MegaMenuBar),
      matchesGoldenFile('goldens/mega_menu_bar_collapsed_1024_dark.png'),
    );
  });

  testWidgets('panel open without promo at 1440 dark', (tester) async {
    await _pumpPanel(tester, const Size(1440, 700), Brightness.dark);
    await expectLater(
      find.byType(MegaMenuPanel),
      matchesGoldenFile('goldens/mega_menu_panel_4col_1440_dark.png'),
    );
  });

  testWidgets('focused bar item shows brand-orange ring at 1440 light',
      (tester) async {
    await _pumpBar(tester, const Size(1440, 600), Brightness.light);
    // Keyboard-focus the first bar item so the focus ring is exercised.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await expectLater(
      find.byType(MegaMenuBar),
      matchesGoldenFile('goldens/mega_menu_bar_focused_1440_light.png'),
    );
  });
}
