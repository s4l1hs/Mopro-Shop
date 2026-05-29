import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/anchored_overlay_panel.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_bar.dart';
import 'package:mopro_api/mopro_api.dart';

import '../../../_support/test_harness.dart';

Category _cat(int id, String name, {int? parentId}) => Category(
      id: id,
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      parentId: parentId,
      commissionPctBps: 1000,
    );

/// Seeds a 3-level taxonomy:
///   Erkek (1)
///     ├─ Giyim (10)
///     │   ├─ T-shirt (100)
///     │   └─ Jean (101)
///     └─ Ayakkabı (11)
///         └─ Sneaker (110)
///   Kadın (2)
///     └─ Çanta (20)
List<Category> _sampleCategories() => [
      _cat(1, 'Erkek'),
      _cat(2, 'Kadın'),
      _cat(10, 'Giyim', parentId: 1),
      _cat(11, 'Ayakkabı', parentId: 1),
      _cat(20, 'Çanta', parentId: 2),
      _cat(100, 'T-shirt', parentId: 10),
      _cat(101, 'Jean', parentId: 10),
      _cat(110, 'Sneaker', parentId: 11),
    ];

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
          builder: (_, state) {
            final id = state.pathParameters['id'] ?? '?';
            return Scaffold(body: Center(child: Text('PLP_$id')));
          },
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  Size size = const Size(1440, 600),
  List<Category>? categories,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Override the categories provider to skip the network call.
        categoriesProvider.overrideWith(
          () => _SeededCategoriesNotifier(categories ?? _sampleCategories()),
        ),
      ],
      child: MaterialApp.router(
        theme: brightness == Brightness.dark
            ? buildDarkTheme()
            : buildLightTheme(),
        routerConfig: _stubRouter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);
  setUp(debugResetAnchoredOverlayPanelRegistry);

  group('MegaMenuBar — render + structure', () {
    testWidgets('renders top-level category labels', (tester) async {
      await _pump(tester);
      expect(find.text('Erkek'), findsOneWidget);
      expect(find.text('Kadın'), findsOneWidget);
      // Subcategories should NOT be visible until a panel opens.
      expect(find.text('Giyim'), findsNothing);
    });

    testWidgets('renders empty when category tree is empty', (tester) async {
      await _pump(tester, categories: const []);
      expect(find.text('Erkek'), findsNothing);
    });
  });

  group('MegaMenuBar — pointer interactions', () {
    testWidgets('label tap routes to category PLP and does NOT open panel',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Erkek'));
      await tester.pumpAndSettle();
      expect(find.text('PLP_1'), findsOneWidget);
      // No panel content should have rendered.
      expect(find.text('Giyim'), findsNothing);
    });

    testWidgets('hover opens panel showing subcategory headers',
        (tester) async {
      await _pump(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Erkek')));
      // Wait past the 80ms open delay.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(); // settle overlay mount
      expect(find.text('Giyim'), findsOneWidget);
      expect(find.text('Ayakkabı'), findsOneWidget);
      // Leaves render too (column structure).
      expect(find.text('T-shirt'), findsOneWidget);
      expect(find.text('Sneaker'), findsOneWidget);
    });
  });
}

class _SeededCategoriesNotifier extends CategoriesNotifier {
  _SeededCategoriesNotifier(this._seed);
  final List<Category> _seed;

  @override
  CategoriesState build() {
    return CategoriesState(categories: AsyncData(_seed));
  }
}
