import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
