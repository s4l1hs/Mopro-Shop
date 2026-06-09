import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:mopro/features/catalog/widgets/home_footer.dart';
import 'package:mopro/widgets/theme_toggle.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_support/test_harness.dart';

void main() {
  setUpAll(initTestEnv);

  testWidgets('renders the info links, language menu and theme toggle',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: HomeFooter()),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('© 2026 Mopro'), findsOneWidget);
    // Untranslated keys render verbatim in tests.
    expect(find.text('footer.about'), findsOneWidget);
    expect(find.text('footer.privacy'), findsOneWidget);
    expect(find.byIcon(Icons.language), findsOneWidget);
    expect(find.byType(ThemeToggle), findsOneWidget);
  });

  group('footer link routing', () {
    Future<void> pumpFooter(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(
              body: SingleChildScrollView(child: HomeFooter()),
            ),
          ),
          GoRoute(
            path: '/help',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('HELP_INDEX'))),
            routes: [
              GoRoute(
                path: 'article/:slug',
                builder: (_, state) => Scaffold(
                  body: Center(child: Text('ARTICLE:${state.pathParameters['slug']}')),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
        ),
      );
      await tester.pump();
    }

    testWidgets('privacy → canonical privacy-and-tracking article',
        (tester) async {
      await pumpFooter(tester);
      await tester.tap(find.text('footer.privacy'));
      await tester.pumpAndSettle();
      expect(find.text('ARTICLE:privacy-and-tracking'), findsOneWidget);
    });

    testWidgets('help → /help index', (tester) async {
      await pumpFooter(tester);
      await tester.tap(find.text('footer.help'));
      await tester.pumpAndSettle();
      expect(find.text('HELP_INDEX'), findsOneWidget);
    });

    testWidgets('about + terms DEFER to /help (nearest hub, no dead tap)',
        (tester) async {
      await pumpFooter(tester);
      await tester.tap(find.text('footer.about'));
      await tester.pumpAndSettle();
      expect(find.text('HELP_INDEX'), findsOneWidget);

      // Back to the footer, then terms.
      await pumpFooter(tester);
      await tester.tap(find.text('footer.terms'));
      await tester.pumpAndSettle();
      expect(find.text('HELP_INDEX'), findsOneWidget);
    });
  });
}
