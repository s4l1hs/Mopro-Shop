import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_form_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

Future<void> _pump(WidgetTester tester, Widget form) async {
  tester.view.physicalSize = const Size(420, 420);
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

  testWidgets('question form light', (tester) async {
    await _pump(tester, const QuestionFormContent(productId: 1));
    await expectLater(
      find.byType(QuestionFormContent),
      matchesGoldenFile('goldens/question_form_light.png'),
    );
  });

  testWidgets('answer form light', (tester) async {
    await _pump(
      tester,
      const AnswerFormContent(productId: 1, questionId: 9),
    );
    await expectLater(
      find.byType(AnswerFormContent),
      matchesGoldenFile('goldens/answer_form_light.png'),
    );
  });
}
