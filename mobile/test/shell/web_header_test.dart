import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/features/favorites/favorites_provider.dart';
import 'package:mopro/shell/web_header.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../_support/stub_unread_count.dart';

import '../_support/test_harness.dart';

/// Minimal AuthNotifier stand-in: lets each test fix the initial state.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._initial);
  final AuthState _initial;
  @override
  Future<AuthState> build() async => _initial;
}

GoRouter _stubRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(
            appBar: WebHeader(),
            body: Center(child: Text('HOME')),
          ),
        ),
        GoRoute(
          path: '/auth/login',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('LOGIN_PAGE'))),
        ),
        GoRoute(
          path: '/favorites',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('FAV_PAGE'))),
        ),
        GoRoute(
          path: '/cart',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('CART_PAGE'))),
        ),
        GoRoute(
          path: '/account',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('ACCOUNT_PAGE'))),
        ),
        GoRoute(
          path: '/search',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('SEARCH_PAGE'))),
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  AuthState authState = const AuthUnauthenticated(),
  int cartCount = 0,
  Size size = const Size(1440, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        stubUnreadCountOverride,
        cartCountProvider.overrideWithValue(cartCount),
        authNotifierProvider.overrideWith(() => _FakeAuthNotifier(authState)),
      ],
      child: MaterialApp.router(
        theme: brightness == Brightness.dark
            ? buildDarkTheme()
            : buildLightTheme(),
        routerConfig: _stubRouter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  group('WebHeader — structure', () {
    testWidgets('renders logo, search pill, icon row', (tester) async {
      await _pump(tester);
      // Logo: MoproLogo renders an Image; search pill exposes search icon.
      expect(find.byIcon(Icons.search), findsOneWidget);
      // Two action icons (favorites + cart) when both have zero counts.
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
    });

    testWidgets('guest variant shows "Giriş Yap" pill', (tester) async {
      await _pump(tester);
      // web_header renders 'auth.login'.tr(); tests don't load the bundle, so
      // .tr() returns the key (auth.login → "Giriş Yap" verified in tr-TR.json).
      expect(find.text('auth.login'), findsOneWidget);
    });

    testWidgets('authed variant shows avatar (initial), not login pill',
        (tester) async {
      await _pump(tester, authState: const AuthAuthenticated());
      expect(find.text('auth.login'), findsNothing);
      // Avatar shows the 'M' placeholder initial.
      expect(find.text('M'), findsOneWidget);
    });
  });

  group('WebHeader — badges', () {
    testWidgets('cart badge shows count when > 0', (tester) async {
      await _pump(tester, cartCount: 3);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('cart badge hidden at zero', (tester) async {
      await _pump(tester);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('cart badge clamps to 99+ over 99', (tester) async {
      await _pump(tester, cartCount: 150);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('favorites badge reflects local favoritesProvider length',
        (tester) async {
      // Pump first to access the container.
      await _pump(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WebHeader)),
      );
      container.read(favoritesProvider.notifier)
        ..toggle(1)
        ..toggle(2);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      // Icon flipped to filled when at least one favorite is set.
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    });
  });

  group('WebHeader — navigation', () {
    testWidgets('cart icon routes to /cart', (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.shopping_bag_outlined));
      await tester.pumpAndSettle();
      expect(find.text('CART_PAGE'), findsOneWidget);
    });

    testWidgets('favorites icon routes to /favorites', (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();
      expect(find.text('FAV_PAGE'), findsOneWidget);
    });

    // Note: in Session 4a the login pill and account avatar no longer
    // navigate on tap — they toggle the AccountHoverMenu instead.
    // Navigation is exercised by `account_hover_menu_test.dart`.
    //
    // The search pill is now a real TextField; submitting routes to
    // `/search?q=<query>`. That flow is exercised by
    // `web_search_pill_test.dart`.
  });

  group('WebHeader — goldens', () {
    testWidgets('1024 light', (tester) async {
      await _pump(tester, size: const Size(1024, 800));
      await expectLater(
        find.byType(WebHeader),
        matchesGoldenFile('goldens/web_header_1024_light.png'),
      );
    });

    testWidgets('1440 light', (tester) async {
      await _pump(tester);
      await expectLater(
        find.byType(WebHeader),
        matchesGoldenFile('goldens/web_header_1440_light.png'),
      );
    });

    testWidgets('1440 dark', (tester) async {
      await _pump(tester, brightness: Brightness.dark);
      await expectLater(
        find.byType(WebHeader),
        matchesGoldenFile('goldens/web_header_1440_dark.png'),
      );
    });
  });
}
