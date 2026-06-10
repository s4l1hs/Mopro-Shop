@Tags(['golden'])
library;

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/account/privacy/privacy_settings_screen.dart';
import 'package:mopro/features/analytics/user_consent_provider.dart';
import 'package:mopro/features/analytics/widgets/consent_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

class _StubConsent extends UserConsentNotifier {
  _StubConsent(this._s);
  final UserConsent _s;
  @override
  UserConsent build() => _s;
}

Future<void> _pump(
  WidgetTester tester,
  UserConsent state,
  Widget child, {
  required double width,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        overrides: [
          userConsentProvider.overrideWith(() => _StubConsent(state)),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
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

  const undecided = UserConsent(authed: true);
  const enabled = UserConsent(authed: true, analyticsEnabled: true);
  const bannerChild = Align(
    alignment: Alignment.bottomCenter,
    child: ConsentBanner(),
  );

  testWidgets('consent banner 1440 light', (tester) async {
    await _pump(
      tester,
      undecided,
      bannerChild,
      width: 1440,
      brightness: Brightness.light,
    );
    await expectLater(
      find.byType(ConsentBanner),
      matchesGoldenFile('goldens/consent_banner_1440_light.png'),
    );
  });

  testWidgets('consent banner 1440 dark', (tester) async {
    await _pump(
      tester,
      undecided,
      bannerChild,
      width: 1440,
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(ConsentBanner),
      matchesGoldenFile('goldens/consent_banner_1440_dark.png'),
    );
  });

  testWidgets('consent banner 375 light', (tester) async {
    await _pump(
      tester,
      undecided,
      bannerChild,
      width: 375,
      brightness: Brightness.light,
    );
    await expectLater(
      find.byType(ConsentBanner),
      matchesGoldenFile('goldens/consent_banner_375_light.png'),
    );
  });

  testWidgets('privacy settings 1440 light', (tester) async {
    await _pump(
      tester,
      enabled,
      const PrivacySettingsScreen(),
      width: 1440,
      brightness: Brightness.light,
    );
    await expectLater(
      find.byType(PrivacySettingsScreen),
      matchesGoldenFile('goldens/privacy_settings_1440_light.png'),
    );
  });

  testWidgets('privacy settings 1440 dark', (tester) async {
    await _pump(
      tester,
      enabled,
      const PrivacySettingsScreen(),
      width: 1440,
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(PrivacySettingsScreen),
      matchesGoldenFile('goldens/privacy_settings_1440_dark.png'),
    );
  });

  testWidgets('privacy delete dialog 1440 light', (tester) async {
    await _pump(
      tester,
      undecided,
      const PrivacySettingsScreen(),
      width: 1440,
      brightness: Brightness.light,
    );
    await tester.tap(find.text('consent.delete_all'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('goldens/privacy_delete_dialog_1440_light.png'),
    );
  });
}