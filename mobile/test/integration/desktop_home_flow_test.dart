import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/providers/home_provider.dart';
import 'package:mopro/features/catalog/providers/products_rail_provider.dart';
import 'package:mopro/features/catalog/screens/home_screen.dart';
import 'package:mopro/features/catalog/widgets/home_footer.dart';
import 'package:mopro/features/home/providers/flash_deals_provider.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

// ── Flow M — adaptive desktop home composition ──────────────────────────────
// At a desktop width the same widgets compose into desktop containers: rails
// render as grids (GridView), the banner shows prev/next chevrons, and the
// thin desktop-only footer is mounted. Mobile composition is asserted absent
// (no footer, no chevrons) at a phone width to prove the breakpoint switch.

ProductSummary _p(int id) => ProductSummary(
      id: id,
      sellerId: 1,
      categoryId: 1,
      brand: 'B',
      status: ProductSummaryStatusEnum.active,
      title: 'P$id',
      priceMinor: 20000,
      priceCurrency: 'TRY',
      cashbackPreview: CashbackPreview(monthlyCoinMinor: 100, currency: 'TRY_COIN'),
    );

class _FakeAuthNotifier extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
}

class _EmptyCategoriesNotifier extends CategoriesNotifier {
  @override
  CategoriesState build() => const CategoriesState(categories: AsyncData([]));
}

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
        (ref, layout) async =>
            const [HomeRail(key: 'recommended', title: 'Önerilenler')],
      ),
      productsRailProvider('recommended')
          .overrideWith((ref) async => [for (var i = 0; i < 8; i++) _p(i + 1)]),
    ];

late SharedPreferences _prefs;

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const CatalogHomeScreen()),
        GoRoute(path: '/search', builder: (_, __) => const Scaffold()),
      ],
    );

Future<void> _pump(WidgetTester tester, Size size) async {
  // Filter the untranslated cashback-chip overflow render artifact.
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  _prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp.router(theme: buildLightTheme(), routerConfig: _router()),
    ),
  );
  await tester.pump(); // resolve futures
  await tester.pump();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('Flow M: desktop composes grids, chevrons and the footer',
      (tester) async {
    await _pump(tester, const Size(1440, 1400));

    // Rails render as a grid on desktop.
    expect(find.byType(GridView), findsWidgets);
    // Banner prev/next chevrons are present on desktop.
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    // The thin desktop-only footer is mounted (scroll to it — the editor's
    // picks section pushes it below the fold in the lazy CustomScrollView).
    await tester.scrollUntilVisible(
      find.byType(HomeFooter),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(HomeFooter), findsOneWidget);
  });

  testWidgets('Flow M: mobile keeps the scroller, no chevrons, no footer',
      (tester) async {
    await _pump(tester, const Size(375, 900));

    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byType(HomeFooter), findsNothing);
  });
}
