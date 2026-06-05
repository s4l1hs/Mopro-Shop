import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/widgets/sort_sheet.dart';

import '../../../_support/test_harness.dart';

void main() {
  setUpAll(initTestEnv);

  // `.tr()` returns the key in tests (no bundle loaded) — assert on the i18n
  // key / RadioListTile.value, never the localized Turkish string.

  testWidgets('renders all six sort options including bestseller (P-029)',
      (tester) async {
    await pumpTrendyolApp(tester, const SortSheet(current: 'recommended'));

    expect(find.byType(RadioListTile<String>), findsNWidgets(6));
    expect(
      find.byWidgetPredicate(
        (w) => w is RadioListTile<String> && w.value == 'bestseller',
      ),
      findsOneWidget,
    );
    expect(find.text('catalog.sort_bestseller'), findsOneWidget);
  });

  testWidgets('bestseller tile is enabled and carries its token', (tester) async {
    // The sheet pops `RadioListTile.value` via onChanged, so a present, enabled
    // tile carrying 'bestseller' means tapping it returns the bestseller token.
    // (The full tap -> sort-state flow is exercised by the desktop dropdown
    // test, which sets f.sort = PlpSort.bestseller.)
    await pumpTrendyolApp(tester, const SortSheet(current: 'recommended'));

    final tile = tester.widget<RadioListTile<String>>(
      find.byWidgetPredicate(
        (w) => w is RadioListTile<String> && w.value == 'bestseller',
      ),
    );
    expect(tile.value, 'bestseller');
    expect(tile.onChanged, isNotNull); // ignore: deprecated_member_use
  });
}
