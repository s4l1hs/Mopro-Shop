import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/catalog/pdp/reviews/review_form_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

Future<void> _pump(
  WidgetTester tester,
  Widget form, {
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(420, 560);
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
          theme: brightness == Brightness.dark
              ? buildDarkTheme()
              : buildLightTheme(),
          home: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: form),
          ),
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

  testWidgets('review form new light', (tester) async {
    await _pump(
      tester,
      const ReviewFormContent(productId: 1),
      brightness: Brightness.light,
    );
    await expectLater(
      find.byType(ReviewFormContent),
      matchesGoldenFile('goldens/review_form_new_light.png'),
    );
  });

  testWidgets('review form new dark', (tester) async {
    await _pump(
      tester,
      const ReviewFormContent(productId: 1),
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(ReviewFormContent),
      matchesGoldenFile('goldens/review_form_new_dark.png'),
    );
  });

  testWidgets('review form edit light', (tester) async {
    await _pump(
      tester,
      const ReviewFormContent(
        productId: 1,
        reviewId: 9,
        initialRating: 4,
        initialTitle: 'Gayet iyi',
        initialBody: 'Kullanışlı, fiyatına göre başarılı bir ürün.',
      ),
      brightness: Brightness.light,
    );
    await expectLater(
      find.byType(ReviewFormContent),
      matchesGoldenFile('goldens/review_form_edit_light.png'),
    );
  });
}
