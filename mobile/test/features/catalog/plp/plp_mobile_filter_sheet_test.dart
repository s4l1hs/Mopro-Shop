import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/widgets/filter_sheet.dart';

import '../../../_support/test_harness.dart';

// PLP-01: the mobile filter sheet now surfaces Brand (searchable) + Rating,
// wired live to plpFiltersProvider (same params the desktop sidebar uses).
// `.tr()` returns keys here (bundle not loaded — see reference_flutter_test_i18n).
// The sheet uses a DraggableScrollableSheet, so it must be opened as a real
// modal (showPlpFilterSheet) rather than pumped bare.

Future<ProviderContainer> _open(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPlpFilterSheet(
                context,
                plpKey: '5',
                brands: const ['Nike', 'Adidas', 'Puma'],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(PlpFilterSheet)));
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('shows Brand + Rating accordions (PLP-01)', (tester) async {
    await _open(tester);
    expect(find.text('plp.filter_brand'), findsOneWidget);
    expect(find.text('plp.filter_rating'), findsOneWidget);
  });

  testWidgets('selecting a brand applies to plpFiltersProvider', (tester) async {
    final container = await _open(tester);
    await tester.tap(find.text('plp.filter_brand')); // expand accordion
    await tester.pumpAndSettle();
    expect(find.text('plp.brand_search'), findsOneWidget); // searchable list
    await tester.tap(find.text('Nike'));
    await tester.pump();
    expect(container.read(plpFiltersProvider('5')).brands, contains('Nike'));
  });

  testWidgets('selecting a rating bucket applies to plpFiltersProvider',
      (tester) async {
    final container = await _open(tester);
    await tester.tap(find.text('plp.filter_rating')); // expand accordion
    await tester.pumpAndSettle();
    await tester.tap(find.text('4')); // the "4 and up" bucket
    await tester.pump();
    expect(container.read(plpFiltersProvider('5')).ratingMin, 4);
  });
}
