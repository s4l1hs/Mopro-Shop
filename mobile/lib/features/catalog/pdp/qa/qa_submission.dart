import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/widgets/adaptive_modal.dart';
import 'package:mopro/core/widgets/login_required_sheet.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_form_content.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_provider.dart';

/// Auth-gated "ask a question" flow. On success refreshes the product's question
/// list (and the user's own list) and shows a confirmation SnackBar.
void openAskQuestion(
  BuildContext context,
  WidgetRef ref, {
  required int productId,
}) {
  requireAuth(
    context,
    ref,
    reason: 'qa.login_to_ask'.tr(),
    onAuthed: () async {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await showAdaptiveModal<bool>(
        context,
        builder: (_) => QuestionFormContent(productId: productId),
      );
      if (ok ?? false) {
        ref
          ..invalidate(questionsProvider(productId))
          ..invalidate(myQuestionsProvider);
        messenger.showSnackBar(
          SnackBar(content: Text('qa.ask_success'.tr())),
        );
      }
    },
  );
}

/// Auth-gated "answer" flow. On success refreshes the question thread and the
/// product's question list (answer count changed) and shows a SnackBar.
void openAnswer(
  BuildContext context,
  WidgetRef ref, {
  required int productId,
  required int questionId,
}) {
  requireAuth(
    context,
    ref,
    reason: 'qa.login_to_answer'.tr(),
    onAuthed: () async {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await showAdaptiveModal<bool>(
        context,
        builder: (_) => AnswerFormContent(
          productId: productId,
          questionId: questionId,
        ),
      );
      if (ok ?? false) {
        ref
          ..invalidate(questionThreadProvider((productId, questionId)))
          ..invalidate(questionsProvider(productId));
        messenger.showSnackBar(
          SnackBar(content: Text('qa.answer_success'.tr())),
        );
      }
    },
  );
}
