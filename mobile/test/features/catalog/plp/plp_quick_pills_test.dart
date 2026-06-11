import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/plp/widgets/plp_quick_pills.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PLP-06: the quick pills write straight through plpFiltersProvider.
const _key = 'test-plp-key';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: PlpQuickPills(plpKey: _key)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders the four quick pills', (tester) async {
    await _pump(tester);
    // The horizontal ListView builds lazily: assert the leading pills first,
    // then scroll the trailing (in-stock) pill into view and assert it (the
    // leading ones may unbuild once scrolled off).
    for (final label in [
      'plp.free_shipping',
      'plp.filter_price_dropped',
      'plp.chip_rating',
    ]) {
      expect(find.widgetWithText(FilterChip, label), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.widgetWithText(FilterChip, 'catalog.filter_in_stock'),
      120,
      scrollable: find.byType(Scrollable),
    );
    expect(
      find.widgetWithText(FilterChip, 'catalog.filter_in_stock'),
      findsOneWidget,
    );
  });

  testWidgets('tapping free-shipping pill toggles the filter on and off',
      (tester) async {
    final container = await _pump(tester);
    // i18n bundle isn't loaded in tests → .tr() returns the key.
    final pill = find.widgetWithText(FilterChip, 'plp.free_shipping');
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(container.read(plpFiltersProvider(_key)).freeShippingOnly, isTrue);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(container.read(plpFiltersProvider(_key)).freeShippingOnly, isFalse);
  });

  testWidgets('rating pill toggles ratingMin 4 ↔ null', (tester) async {
    final container = await _pump(tester);
    final pill = find.widgetWithText(FilterChip, 'plp.chip_rating');
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(container.read(plpFiltersProvider(_key)).ratingMin, 4);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(container.read(plpFiltersProvider(_key)).ratingMin, isNull);
  });
}
