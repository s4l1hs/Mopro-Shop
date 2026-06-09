import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/widgets/home_category_rail.dart';
import 'package:mopro_api/mopro_api.dart';

import '../../../_support/test_harness.dart';

/// Seeds a few root categories so the rail renders its circular pucks (G-4)
/// instead of collapsing to SizedBox.shrink on the empty Home-golden seed.
class _SeededCategoriesNotifier extends CategoriesNotifier {
  @override
  CategoriesState build() => CategoriesState(
        categories: AsyncData([
          _cat(1, 'Elektronik', 'elektronik'),
          _cat(2, 'Giyim', 'giyim'),
          _cat(3, 'Spor', 'spor'),
          _cat(4, 'Kozmetik', 'kozmetik'),
        ]),
      );

  static Category _cat(int id, String name, String slug) => Category(
        id: id,
        name: name,
        slug: slug,
        commissionPctBps: 1000,
      );
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('renders a puck per root category + the all-categories entry',
      (tester) async {
    tester.view
      ..physicalSize = const Size(375, 200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpTrendyolApp(
      tester,
      const HomeCategoryRail(),
      overrides: [
        categoriesProvider.overrideWith(_SeededCategoriesNotifier.new),
      ],
    );
    await tester.pump();

    // 6 roots → at least the first puck label renders; tests return i18n keys.
    expect(find.text('Elektronik'), findsOneWidget);
    expect(find.text('home.all_categories'), findsOneWidget);
  });

  // HOME-POP-01 §3.2: golden coverage for the circular category pucks (G-4).
  // Previously ∅ coverage — the Home golden seeds empty categories so the rail
  // collapses.
  testWidgets('golden: populated puck rail', (tester) async {
    tester.view
      ..physicalSize = const Size(375, 200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpTrendyolApp(
      tester,
      const HomeCategoryRail(),
      overrides: [
        categoriesProvider.overrideWith(_SeededCategoriesNotifier.new),
      ],
    );
    await tester.pump();

    await expectLater(
      find.byType(HomeCategoryRail),
      matchesGoldenFile('goldens/home_category_rail.png'),
    );
  });
}
