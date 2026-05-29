import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/providers/home_provider.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
import 'package:mopro/features/catalog/screens/home_screen.dart';
import 'package:mopro/features/home/providers/flash_deals_provider.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines are generated on Linux/CI via `make update-goldens`
// (`golden-rebaseline` workflow); the platform guard fails these on non-CI
// platforms with a remediation message rather than a pixel diff.

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 1,
      brand: 'B',
      status: ProductSummaryStatusEnum.active,
      title: 'Ürün $id',
      priceMinor: 20000 + id * 1000,
      priceCurrency: 'TRY',
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 120, currency: 'TRY_COIN'),
    );

class _FakeAuthNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
}

class _EmptyCategoriesNotifier extends CategoriesNotifier {
  @override
  CategoriesState build() => const CategoriesState(categories: AsyncData([]));
}

late SharedPreferences _prefs;

List<Override> _overrides() => [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      authNotifierProvider.overrideWith(_FakeAuthNotifier.new),
      categoriesProvider.overrideWith(_EmptyCategoriesNotifier.new),
      flashDealsProvider.overrideWith((ref) async => null),
      homeBannersProvider.overrideWith(
        (ref) async => const [
          HomeBanner(id: 1, imageUrl: 'https://x.test/a.png', deepLink: '/'),
          HomeBanner(id: 2, imageUrl: 'https://x.test/b.png', deepLink: '/'),
        ],
      ),
      homeMoodStoriesProvider.overrideWith((ref) async => const []),
      trendingSearchesProvider.overrideWith((ref) async => const <String>[]),
      homeRailsProvider.overrideWith(
        (ref) async =>
            const [HomeRail(key: 'recommended', title: 'Sizin için seçtiklerimiz')],
      ),
      productsRailProvider('recommended')
          .overrideWith((ref) async => [for (var i = 0; i < 8; i++) _p(i + 1)]),
    ];

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const CatalogHomeScreen()),
        GoRoute(path: '/search', builder: (_, __) => const Scaffold()),
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
        overrides: _overrides(),
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
    // EasyLocalization caches translations to a temp dir; without the plugin
    // that throws MissingPluginException (fatal on the heavy home tree). Mock
    // the path_provider channel so the cache write succeeds.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('home mobile 375', (tester) async {
    await _pump(tester, const Size(375, 2400));
    await expectLater(
      find.byType(CatalogHomeScreen),
      matchesGoldenFile('goldens/home_mobile_375.png'),
    );
  });

  testWidgets('home tablet 768', (tester) async {
    await _pump(tester, const Size(768, 2400));
    await expectLater(
      find.byType(CatalogHomeScreen),
      matchesGoldenFile('goldens/home_tablet_768.png'),
    );
  });

  testWidgets('home desktop 1440', (tester) async {
    await _pump(tester, const Size(1440, 2400));
    await expectLater(
      find.byType(CatalogHomeScreen),
      matchesGoldenFile('goldens/home_desktop_1440.png'),
    );
  });
}
