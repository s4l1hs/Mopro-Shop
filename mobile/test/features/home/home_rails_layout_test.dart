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
import 'package:mopro/features/home/home_recommendations_provider.dart';
import 'package:mopro/features/home/providers/flash_deals_provider.dart';
import 'package:mopro_api/mopro_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_support/test_harness.dart';

// §6.3 / §2.5 fixture: the home screen hints `?layout=` from the breakpoint, and
// the server returns up to 6 rails for desktop / 3 for mobile. Here the
// homeRailsProvider override returns 6 vs 3 by layout; we assert the rendered
// rail-title count matches.

class _FakeAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
}

class _EmptyCategories extends CategoriesNotifier {
  @override
  CategoriesState build() => const CategoriesState(categories: AsyncData([]));
}

class _EmptyHomeRecs extends HomeRecommendationsNotifier {
  @override
  AsyncValue<HomeRecommendations> build() =>
      const AsyncValue.data(HomeRecommendations.empty);
}

late SharedPreferences _prefs;

List<Override> _overrides() => [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      authNotifierProvider.overrideWith(_FakeAuth.new),
      homeRecommendationsProvider.overrideWith(_EmptyHomeRecs.new),
      categoriesProvider.overrideWith(_EmptyCategories.new),
      flashDealsProvider.overrideWith((ref) async => null),
      homeBannersProvider.overrideWith((ref) async => const []),
      homeMoodStoriesProvider.overrideWith((ref) async => const []),
      trendingSearchesProvider.overrideWith((ref) async => const <String>[]),
      productsRailProvider.overrideWith((ref, key) async => const <ProductSummary>[]),
      homeRailsProvider.overrideWith(
        (ref, layout) async => [
          for (var i = 0; i < (layout == 'desktop' ? 6 : 3); i++)
            HomeRail(key: 'r$i', title: 'Rail $i'),
        ],
      ),
    ];

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const CatalogHomeScreen()),
        GoRoute(path: '/search', builder: (_, __) => const Scaffold()),
      ],
    );

Future<void> _pump(WidgetTester tester, Size size) async {
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
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('desktop renders 6 rails (layout=desktop)', (tester) async {
    await _pump(tester, const Size(1440, 3000));
    expect(find.text('Rail 0'), findsOneWidget);
    expect(find.text('Rail 5'), findsOneWidget);
  });

  testWidgets('mobile renders 3 rails (layout=mobile)', (tester) async {
    await _pump(tester, const Size(375, 3000));
    expect(find.text('Rail 0'), findsOneWidget);
    expect(find.text('Rail 2'), findsOneWidget);
    expect(find.text('Rail 3'), findsNothing);
    expect(find.text('Rail 5'), findsNothing);
  });
}
