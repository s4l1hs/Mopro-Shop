import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/features/seller/data/seller_size_chart_repository.dart';
import 'package:mopro/features/seller/screens/seller_size_chart_editor_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repo fake: create surfaces a 422 validation message; copy-from-standard
/// returns a two-size EN baseline.
class _FakeRepo extends SellerSizeChartRepository {
  _FakeRepo() : super(Dio());

  @override
  Future<int> createChart(SellerSizeChart chart) async =>
      throw const SizeChartValidationException(
          'invalid size chart: "chest" not monotonic at L');

  @override
  Future<SellerSizeChart?> fetchStandard({
    required String garmentType,
    required String gender,
    String sizeSystem = 'alpha',
  }) async =>
      const SellerSizeChart(
        id: 0,
        name: '',
        garmentType: 'top',
        gender: 'female',
        sizeSystem: 'alpha',
        source: 'standard',
        rows: [
          SizeChartRow(
              sizeLabel: 'M',
              sortRank: 3,
              measurement: 'chest',
              minMm: 900,
              maxMm: 980),
          SizeChartRow(
              sizeLabel: 'L',
              sortRank: 4,
              measurement: 'chest',
              minMm: 980,
              maxMm: 1060),
        ],
      );
}

Future<void> _pump(WidgetTester tester) async {
  // Tall viewport so the whole form (incl. the bottom Save button) builds in the
  // lazy ListView without scrolling.
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sellerSizeChartRepositoryProvider.overrideWithValue(_FakeRepo()),
        ],
        child: const MaterialApp(home: SellerSizeChartEditorScreen()),
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

  testWidgets('save → surfaces the 422 validation reason inline', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('seller.chart_save'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('not monotonic'), findsOneWidget);
  });

  testWidgets('copy-from-standard prefills the EN size rows', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('seller.chart_copy_standard'));
    await tester.pump();
    await tester.pump();
    // Two size cards prefilled from the standard chart (labels M and L).
    expect(find.text('M'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    // The min/max mm values are filled in.
    expect(find.text('900'), findsOneWidget);
    expect(find.text('1060'), findsOneWidget);
  });
}
