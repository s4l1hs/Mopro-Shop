import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/features/catalog/providers/category_tree_provider.dart';
import 'package:mopro/features/web/mega_menu/mega_menu_panel.dart';
import 'package:mopro/features/web/mega_menu/promo_image_placeholder.dart';
import 'package:mopro_api/mopro_api.dart';

import '../../../_support/test_harness.dart';

Category _cat(int id, String name, {int? parentId, CategoryPromoSlot? promo}) =>
    Category(
      id: id,
      name: name,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      parentId: parentId,
      promoSlot: promo,
      commissionPctBps: 1000,
    );

CategoryNode _node(Category c, [List<CategoryNode>? children]) =>
    CategoryNode(category: c, children: children);

/// Builds a top-level category with 2 subcategories, each carrying 2 leaves.
/// Optional `promo` parameter attaches a CategoryPromoSlot to the top-level.
CategoryNode _seedTopLevel({CategoryPromoSlot? promo}) {
  final leaf1 = _node(_cat(100, 'T-shirt', parentId: 10));
  final leaf2 = _node(_cat(101, 'Jean', parentId: 10));
  final leaf3 = _node(_cat(110, 'Sneaker', parentId: 11));
  final leaf4 = _node(_cat(111, 'Bot', parentId: 11));
  final sub1 = _node(_cat(10, 'Giyim', parentId: 1), [leaf1, leaf2]);
  final sub2 = _node(_cat(11, 'Ayakkabı', parentId: 1), [leaf3, leaf4]);
  return _node(_cat(1, 'Erkek', promo: promo), [sub1, sub2]);
}

GoRouter _stubRouter(Widget panel) => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(body: panel),
        ),
        GoRoute(
          // Captures the promo destination too — the query string is
          // surfaced into the label so tests can verify the deep_link
          // round-tripped intact.
          path: '/categories/:id',
          builder: (_, state) {
            final id = state.pathParameters['id'] ?? '?';
            final campaign = state.uri.queryParameters['campaign'];
            final label = campaign == null
                ? 'PLP_$id'
                : 'PLP_${id}_campaign_$campaign';
            return Scaffold(body: Center(child: Text(label)));
          },
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required CategoryNode active,
  Size size = const Size(1440, 600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: _stubRouter(
        MegaMenuPanel(active: active, onDismiss: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  group('MegaMenuPanel — layout switch', () {
    testWidgets('renders 4-column subcategory grid when promoSlot is null',
        (tester) async {
      await _pump(tester, active: _seedTopLevel());
      // Subcategory headers visible.
      expect(find.text('Giyim'), findsOneWidget);
      expect(find.text('Ayakkabı'), findsOneWidget);
      // Promo column not present — no CTA button text.
      expect(find.text('mega_menu.promo.cta'), findsNothing);
      // PromoImagePlaceholder not present.
      expect(find.byType(PromoImagePlaceholder), findsNothing);
    });

    testWidgets('renders 3+1 layout when promoSlot is present',
        (tester) async {
      final promo = CategoryPromoSlot(
        imageUrl: 'https://example.test/promo.png',
        title: 'Spring Sale',
        deepLink: '/categories/1?campaign=spring',
      );
      await _pump(tester, active: _seedTopLevel(promo: promo));
      // Promo column content visible.
      expect(find.text('Spring Sale'), findsOneWidget);
      expect(find.text('mega_menu.promo.cta'), findsOneWidget);
      // Subcategory headers still visible.
      expect(find.text('Giyim'), findsOneWidget);
    });
  });

  group('MegaMenuPanel — promo column behavior', () {
    testWidgets('tapping the promo CTA routes to promo.deepLink',
        (tester) async {
      final promo = CategoryPromoSlot(
        imageUrl: 'https://example.test/promo.png',
        title: 'Spring Sale',
        deepLink: '/categories/1?campaign=spring',
      );
      await _pump(tester, active: _seedTopLevel(promo: promo));
      await tester.tap(find.text('mega_menu.promo.cta'));
      await tester.pumpAndSettle();
      expect(find.text('PLP_1_campaign_spring'), findsOneWidget);
    });

    testWidgets('long title clamps to 2 lines with ellipsis', (tester) async {
      final promo = CategoryPromoSlot(
        imageUrl: 'https://example.test/promo.png',
        title:
            'This is an extremely long promo title that should clamp to '
            'exactly two lines and not overflow the panel layout under any '
            'circumstances',
        deepLink: '/categories/1',
      );
      await _pump(tester, active: _seedTopLevel(promo: promo));
      // Find the Text widget rendering the title — has maxLines: 2 + ellipsis
      // via TextOverflow.ellipsis.
      final titleFinder = find.textContaining('extremely long promo');
      expect(titleFinder, findsOneWidget);
      final widget = tester.widget<Text>(titleFinder);
      expect(widget.maxLines, 2);
      expect(widget.overflow, TextOverflow.ellipsis);
    });
  });

  group('PromoImagePlaceholder — standalone render', () {
    testWidgets('renders icon + caption text when invoked directly',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320, height: 180,
                child: PromoImagePlaceholder(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.text('mega_menu.promo.image_unavailable'), findsOneWidget);
    });
  });
}
