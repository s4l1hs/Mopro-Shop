import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/catalog/pdp/qa/answer_row.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_provider.dart';
import 'package:mopro/features/catalog/pdp/qa/question_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Baselines generated on Linux/CI via the golden-rebaseline workflow.

final _question = Question(
  id: 1,
  productId: 1,
  userId: 100,
  authorName: 'Ayşe K.',
  body: 'Bedeni dar mı kalıyor, bir beden büyük mü almalıyım?',
  answerCount: 3,
  createdAt: DateTime.utc(2026, 5, 1, 10),
);

final _sellerAnswer = Answer(
  id: 1,
  questionId: 1,
  userId: 5,
  authorName: 'Acme Store',
  isSeller: true,
  body: 'Normal kalıp, kendi bedeninizi tercih edebilirsiniz.',
  createdAt: DateTime.utc(2026, 5, 2, 10),
);

final _userAnswer = Answer(
  id: 2,
  questionId: 1,
  userId: 101,
  authorName: 'Mehmet T.',
  isSeller: false,
  body: 'Bence tam kalıp, ben kendi bedenimi aldım ve oldu.',
  createdAt: DateTime.utc(2026, 5, 3, 10),
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(420, 240);
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
          body: Padding(padding: const EdgeInsets.all(16), child: child),
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

  testWidgets('question row light', (tester) async {
    await _pump(
      tester,
      QuestionRow(question: _question, onTap: () {}),
      brightness: Brightness.light,
    );
    await expectLater(
      find.byType(QuestionRow),
      matchesGoldenFile('goldens/question_row_light.png'),
    );
  });

  testWidgets('question row dark', (tester) async {
    await _pump(
      tester,
      QuestionRow(question: _question, onTap: () {}),
      brightness: Brightness.dark,
    );
    await expectLater(
      find.byType(QuestionRow),
      matchesGoldenFile('goldens/question_row_dark.png'),
    );
  });

  testWidgets('answer row seller light', (tester) async {
    await _pump(
      tester,
      AnswerRow(answer: _sellerAnswer),
      brightness: Brightness.light,
    );
    await expectLater(
      find.byType(AnswerRow),
      matchesGoldenFile('goldens/answer_row_seller_light.png'),
    );
  });

  testWidgets('answer row user light', (tester) async {
    await _pump(
      tester,
      AnswerRow(answer: _userAnswer),
      brightness: Brightness.light,
    );
    await expectLater(
      find.byType(AnswerRow),
      matchesGoldenFile('goldens/answer_row_user_light.png'),
    );
  });
}
