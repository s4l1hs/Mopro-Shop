import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/widgets/product_list_rail.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

late SharedPreferences _prefs;

List<ProductSummary> _products(int n) => [
      for (var i = 0; i < n; i++)
        ProductSummary(
          id: i + 1,
          sellerId: 1,
          categoryId: 42,
          brand: 'Acme',
          status: ProductSummaryStatusEnum.active,
          title: 'Ürün ${i + 1}',
          priceMinor: 12900 + i * 1000,
          priceCurrency: 'TRY',
          cashbackPreview:
              CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
        ),
    ];

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = Size(width, 360);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: ProductListRail(
                products: _products(6),
                title: 'Son baktıkların',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _prefs = await SharedPreferences.getInstance();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('product list rail 1440 light', (tester) async {
    await _pump(tester, width: 1440, brightness: Brightness.light);
    await expectLater(
      find.byType(ProductListRail),
      matchesGoldenFile('goldens/product_list_rail_1440_light.png'),
    );
  });

  testWidgets('product list rail 1440 dark', (tester) async {
    await _pump(tester, width: 1440, brightness: Brightness.dark);
    await expectLater(
      find.byType(ProductListRail),
      matchesGoldenFile('goldens/product_list_rail_1440_dark.png'),
    );
  });

  testWidgets('product list rail 375 light', (tester) async {
    await _pump(tester, width: 375, brightness: Brightness.light);
    await expectLater(
      find.byType(ProductListRail),
      matchesGoldenFile('goldens/product_list_rail_375_light.png'),
    );
  });
}
