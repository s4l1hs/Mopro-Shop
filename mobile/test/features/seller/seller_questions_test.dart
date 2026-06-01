import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/catalog/pdp/qa/answer_row.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_provider.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';
import 'package:mopro/features/seller/screens/seller_question_detail_screen.dart';
import 'package:mopro/features/seller/screens/seller_questions_inbox_screen.dart';

import '../../_support/test_harness.dart';

SellerQuestion _q(int id, {int answers = 0}) => SellerQuestion(
      id: id,
      productId: 100 + id,
      userId: 7000 + id,
      body: 'Bu ürün su geçirmez mi? #$id',
      answerCount: answers,
      createdAt: DateTime.utc(2026, 5, 2),
    );

class _FakeRepo extends SellerRepository {
  _FakeRepo({this.questions = const []}) : super(Dio());
  final List<SellerQuestion> questions;

  @override
  Future<(List<SellerQuestion>, int, bool)> listQuestions({
    required bool unanswered,
    int page = 1,
    int pageSize = 20,
  }) async {
    final filtered =
        unanswered ? questions.where((q) => !q.isAnswered).toList() : questions;
    return (filtered, filtered.length, false);
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildLightTheme(), home: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('inbox renders a row per unanswered question', (tester) async {
    await _pump(
      tester,
      const SellerQuestionsInboxScreen(),
      overrides: [
        sellerRepositoryProvider
            .overrideWithValue(_FakeRepo(questions: [_q(1), _q(2)])),
      ],
    );
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.text('seller.q_awaiting'), findsNWidgets(2));
  });

  testWidgets('unanswered-empty shows the celebration copy', (tester) async {
    await _pump(
      tester,
      const SellerQuestionsInboxScreen(),
      overrides: [
        // Only answered questions exist → unanswered filter is empty.
        sellerRepositoryProvider
            .overrideWithValue(_FakeRepo(questions: [_q(1, answers: 1)])),
      ],
    );
    expect(find.text('seller.questions_empty_unanswered'), findsOneWidget);
  });

  testWidgets('detail shows the question + existing answers + composer CTA',
      (tester) async {
    final thread = QuestionThread(
      question: Question(
        id: 10,
        productId: 110,
        userId: 7010,
        authorName: 'Müşteri',
        body: 'Kargo ne zaman gelir?',
        answerCount: 1,
        createdAt: DateTime.utc(2026, 5, 2),
      ),
      answers: [
        Answer(
          id: 1,
          questionId: 10,
          userId: 1,
          authorName: 'Acme Store',
          isSeller: true,
          body: '2 iş günü içinde.',
          createdAt: DateTime.utc(2026, 5, 2),
        ),
      ],
    );
    await _pump(
      tester,
      SellerQuestionDetailScreen(questionId: 10, initial: _q(10)),
      overrides: [
        questionThreadProvider((110, 10)).overrideWith((ref) async => thread),
      ],
    );
    expect(find.text('Kargo ne zaman gelir?'), findsOneWidget);
    expect(find.byType(AnswerRow), findsOneWidget);
    // "Cevap Yaz" CTA (reuses seller.answer_questions label).
    expect(find.text('seller.answer_questions'), findsOneWidget);
  });
}
