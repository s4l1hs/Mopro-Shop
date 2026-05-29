import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Minimal app that wires the theme controller into MaterialApp.themeMode, and
// surfaces the *resolved* brightness as text so we can assert what the user
// actually sees (independent of the OS brightness).
Widget _app(SharedPreferences prefs) => ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: Consumer(
        builder: (context, ref, _) {
          final mode = ref.watch(themeControllerProvider);
          return MaterialApp(
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            themeMode: mode,
            home: Builder(
              builder: (c) => Text(
                Theme.of(c).brightness == Brightness.dark ? 'DARK' : 'LIGHT',
                textDirection: TextDirection.ltr,
              ),
            ),
          );
        },
      ),
    );

void main() {
  // ── Flow L — theme default boot ─────────────────────────────────────────
  testWidgets(
      'Flow L: fresh install boots light under mocked dark OS; switch dark; '
      'cold-restart preserves dark', (tester) async {
    // Mock the OS brightness to dark — the app must NOT follow it.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    // Fresh install → light, despite the dark OS brightness.
    await tester.pumpWidget(_app(prefs));
    await tester.pumpAndSettle();
    expect(find.text('LIGHT'), findsOneWidget);
    expect(find.text('DARK'), findsNothing);

    // User switches to dark.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(themeControllerProvider.notifier).setMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(find.text('DARK'), findsOneWidget);
    expect(prefs.getString('mopro_theme_mode'), 'dark');

    // Cold restart: rebuild the app from the persisted prefs store.
    final prefs2 = await SharedPreferences.getInstance(); // same mock store
    await tester.pumpWidget(_app(prefs2));
    await tester.pumpAndSettle();
    expect(find.text('DARK'), findsOneWidget); // dark choice preserved
  });
}
