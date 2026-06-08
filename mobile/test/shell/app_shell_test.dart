import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/cart/application/cart_count_provider.dart';
import 'package:mopro/shell/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_support/test_harness.dart';

/// Minimal go_router that mounts AppShell with 5 placeholder branches.
GoRouter _shellRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, __, shell) => AppShell(navigationShell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, __) =>
                      const Center(key: Key('homeBody'), child: Text('Home')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/categories',
                  builder: (_, __) => const Center(child: Text('Categories')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/favorites',
                  builder: (_, __) => const Center(child: Text('Favorites')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/cart',
                  builder: (_, __) => const Center(child: Text('Cart')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/account',
                  builder: (_, __) => const Center(child: Text('Account')),
                ),
              ],
            ),
          ],
        ),
      ],
    );

Future<void> _pumpShell(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  // Default to mobile width so the existing bottom-nav structure tests
  // resolve through the mobile branch of the new adaptive AppShell.
  // Web-branch tests should pass an explicit Size(>=600, ...).
  Size size = const Size(390, 720),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cartCountProvider.overrideWithValue(0),
      ],
      child: MaterialApp.router(
        theme: brightness == Brightness.dark
            ? buildDarkTheme()
            : buildLightTheme(),
        routerConfig: _shellRouter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  group('BottomNavBar structure', () {
    testWidgets('renders all 5 tab labels', (tester) async {
      await _pumpShell(tester);
      // Bottom nav labels (Turkish defaults via easy_localization fallback)
      // easy_localization isn't initialized in tests so it returns the key.
      // Match by partial label text or fallback to icon presence.
      expect(find.byIcon(Icons.home), findsOneWidget); // active home
      // IA-01: slot 1 is the Coin tab (was Categories/grid_view).
      expect(find.byIcon(Icons.monetization_on_outlined), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    });

    testWidgets('tapping Coin tab switches active icon', (tester) async {
      await _pumpShell(tester);
      // Initially home is active (filled).
      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(find.byIcon(Icons.monetization_on_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.monetization_on_outlined));
      await tester.pumpAndSettle();

      // After tap, Coin should be active (filled icon)
      expect(find.byIcon(Icons.monetization_on), findsOneWidget);
      // Home is now inactive (outlined)
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    });
  });

  group('BottomNavBar golden', () {
    testWidgets('light theme', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 120));
      await _pumpShell(tester);
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/bottom_nav_light.png'),
      );
    });

    testWidgets('dark theme', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 120));
      await _pumpShell(tester, brightness: Brightness.dark);
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/bottom_nav_dark.png'),
      );
    });
  });
}
