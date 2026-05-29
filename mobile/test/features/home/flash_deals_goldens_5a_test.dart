import 'dart:io';

import 'package:clock/clock.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/home/providers/flash_deals_provider.dart';
import 'package:mopro/features/home/widgets/flash_deals_rail.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines are generated on Linux/CI via `make update-goldens`; the platform
// guard fails these on non-CI platforms with a remediation message.

final _now = DateTime.utc(2026, 6, 1, 12);

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 1,
      brand: 'B',
      status: ProductSummaryStatusEnum.active,
      title: 'Ürün $id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      flashPriceMinor: 13999,
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
    );

FlashDealsCollection _col() => FlashDealsCollection(
      id: 1,
      title: 'Bugünün Fırsatları',
      endsAt: _now.add(const Duration(hours: 2, minutes: 30)),
      products: [for (var i = 0; i < 8; i++) _p(i + 1)],
    );

late SharedPreferences _prefs;

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) =>
              const Scaffold(body: SingleChildScrollView(child: FlashDealsRail())),
        ),
        GoRoute(path: '/products/:id', builder: (_, __) => const Scaffold()),
      ],
    );

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  _prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(_prefs),
          flashDealsProvider.overrideWith((ref) async => _col()),
        ],
        child: MaterialApp.router(
          theme: buildLightTheme(),
          routerConfig: _router(),
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
    // See home_goldens_5a_test.dart: mock path_provider so EasyLocalization's
    // translation cache write doesn't throw MissingPluginException.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('flash deals mobile 375', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _pump(tester, const Size(375, 700));
      await expectLater(
        find.byType(FlashDealsRail),
        matchesGoldenFile('goldens/flash_deals_mobile_375.png'),
      );
    });
  });

  testWidgets('flash deals desktop 1440', (tester) async {
    await withClock(Clock.fixed(_now), () async {
      await _pump(tester, const Size(1440, 900));
      await expectLater(
        find.byType(FlashDealsRail),
        matchesGoldenFile('goldens/flash_deals_desktop_1440.png'),
      );
    });
  });
}
