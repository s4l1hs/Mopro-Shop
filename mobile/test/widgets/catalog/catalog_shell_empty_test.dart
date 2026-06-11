import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/widgets/catalog/catalog_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PLP-08: the no-results state shows a "clear filters" CTA only when the empty
// grid is caused by active filters (activeFilterCount > 0 + onClearFilters wired).
Future<void> _pump(
  WidgetTester tester, {
  required int activeFilterCount,
  VoidCallback? onClearFilters,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: MaterialApp(
        home: Scaffold(
          body: CatalogShell(
            products: const [],
            isLoading: false,
            hasMore: false,
            loadingMore: false,
            onLoadMore: () {},
            activeFilterCount: activeFilterCount,
            onClearFilters: onClearFilters,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('empty + active filters → clear-filters CTA, taps callback',
      (tester) async {
    var cleared = false;
    await _pump(tester,
        activeFilterCount: 2, onClearFilters: () => cleared = true);
    // i18n bundle isn't loaded in tests → .tr() returns the key.
    final cta = find.text('empty_state.clear_filters');
    expect(cta, findsOneWidget);
    await tester.tap(cta);
    expect(cleared, isTrue);
  });

  testWidgets('empty + no active filters → bare empty state, no CTA',
      (tester) async {
    await _pump(tester, activeFilterCount: 0, onClearFilters: () {});
    expect(find.text('empty_state.clear_filters'), findsNothing);
    expect(find.text('empty_state.empty_message'), findsOneWidget);
  });
}
