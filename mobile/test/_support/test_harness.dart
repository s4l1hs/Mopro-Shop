import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Disables Google Fonts runtime fetching so golden tests are deterministic.
/// Inter falls back to the system Material default in tests.
Future<void> initTestEnv() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues(<String, Object>{});
}

/// Pumps a widget inside a ProviderScope + MaterialApp configured with the
/// Mopro brand theme. Pass [brightness] to switch between light and dark.
Future<void> pumpTrendyolApp(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  List<Override> overrides = const [],
}) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...overrides,
      ],
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? buildDarkTheme()
            : buildLightTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}
