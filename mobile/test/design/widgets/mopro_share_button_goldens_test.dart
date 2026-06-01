import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/widgets/mopro_share_button.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(200, 120);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('tr', 'TR')],
      path: 'assets/translations',
      fallbackLocale: const Locale('tr', 'TR'),
      child: ProviderScope(
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const Scaffold(
            body: Center(
              child: MoproShareButton(
                url: 'https://mopro.shop/products/1',
                title: 'Ürün',
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('share button idle 1440 light', (tester) async {
    await _pump(tester);
    await expectLater(
      find.byType(MoproShareButton),
      matchesGoldenFile('goldens/share_button_idle_light.png'),
    );
  });
}
