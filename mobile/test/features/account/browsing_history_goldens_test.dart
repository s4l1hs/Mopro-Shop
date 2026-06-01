import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/account/browsing_history_screen.dart';
import 'package:mopro/features/home/recently_viewed_provider.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow; the
// platform guard fails these on macOS with a remediation message.

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 1,
      brand: 'B',
      status: ProductSummaryStatusEnum.active,
      title: 'Ürün $id',
      priceMinor: 20000 + id * 1000,
      priceCurrency: 'TRY',
      cashbackPreview:
          CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
    );

class _FakeRecentlyViewed extends RecentlyViewedNotifier {
  _FakeRecentlyViewed(this._v);
  final List<ProductSummary> _v;
  @override
  AsyncValue<List<ProductSummary>> build() => AsyncData(_v);
}

late SharedPreferences _prefs;

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  required List<ProductSummary> products,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  _prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/account/browsing-history',
    routes: [
      GoRoute(
        path: '/account/browsing-history',
        builder: (_, __) => const BrowsingHistoryScreen(),
      ),
      GoRoute(path: '/products/:id', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/', builder: (_, __) => const Scaffold()),
    ],
  );

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_prefs),
          recentlyViewedProvider
              .overrideWith(() => _FakeRecentlyViewed(products)),
        ],
        child: MaterialApp.router(
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          routerConfig: router,
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
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  final populated = [for (var i = 1; i <= 6; i++) _p(i)];

  testWidgets('browsing history populated 1440 light', (tester) async {
    await _pump(tester, const Size(1440, 900), products: populated);
    await expectLater(
      find.byType(BrowsingHistoryScreen),
      matchesGoldenFile('goldens/browsing_history_populated_1440_light.png'),
    );
  });

  testWidgets('browsing history populated 1440 dark', (tester) async {
    await _pump(
      tester,
      const Size(1440, 900),
      products: populated,
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(BrowsingHistoryScreen),
      matchesGoldenFile('goldens/browsing_history_populated_1440_dark.png'),
    );
  });

  testWidgets('browsing history populated 375 light', (tester) async {
    await _pump(tester, const Size(375, 800), products: populated);
    await expectLater(
      find.byType(BrowsingHistoryScreen),
      matchesGoldenFile('goldens/browsing_history_populated_375_light.png'),
    );
  });

  testWidgets('browsing history empty 1440 light', (tester) async {
    await _pump(tester, const Size(1440, 900), products: const []);
    await expectLater(
      find.byType(BrowsingHistoryScreen),
      matchesGoldenFile('goldens/browsing_history_empty_1440_light.png'),
    );
  });

  testWidgets('browsing history empty 1440 dark', (tester) async {
    await _pump(
      tester,
      const Size(1440, 900),
      products: const [],
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(BrowsingHistoryScreen),
      matchesGoldenFile('goldens/browsing_history_empty_1440_dark.png'),
    );
  });
}
