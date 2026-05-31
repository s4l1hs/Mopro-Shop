import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/widgets/skip_to_content_link.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

void main() {
  testWidgets('off-screen until focused, then revealed at top-left',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SkipToContentLink(onSkip: () {}),
          ),
        ),
      ),
    );
    final text = find.text('a11y.skip_to_content');
    // Unfocused: translated far off-screen (negative x).
    expect(tester.getTopLeft(text).dx, lessThan(-1000));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    // Focused: back on-screen.
    expect(tester.getTopLeft(text).dx, greaterThanOrEqualTo(0));
  });

  testWidgets('Enter on the focused link invokes onSkip', (tester) async {
    var skipped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SkipToContentLink(onSkip: () => skipped++),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(skipped, 1);
  });

  group('goldens', () {
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

    for (final brightness in Brightness.values) {
      final b = brightness == Brightness.dark ? 'dark' : 'light';
      testWidgets('skip link focused 1024 $b', (tester) async {
        tester.view.physicalSize = const Size(1024, 200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('tr', 'TR')],
            path: 'assets/translations',
            fallbackLocale: const Locale('tr', 'TR'),
            child: MaterialApp(
              theme: brightness == Brightness.dark
                  ? buildDarkTheme()
                  : buildLightTheme(),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SkipToContentLink(onSkip: () {}),
                ),
              ),
            ),
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(SkipToContentLink),
          matchesGoldenFile('goldens/skip_to_content_link_focused_1024_$b.png'),
        );
      });
    }
  });
}
