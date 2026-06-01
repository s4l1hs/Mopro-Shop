import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/utils/relative_time.dart';
import 'package:mopro/features/catalog/pdp/qa/answer_row.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_provider.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_submission.dart';
import 'package:mopro/features/seller/data/seller_repository.dart';
import 'package:mopro/features/seller/providers/seller_questions_provider.dart';

/// `/seller/questions/:id` — question + existing answers + a "Cevap Yaz"
/// composer. Reuses the Q&A thread provider, AnswerRow, and openAnswer (which
/// posts via the existing answers endpoint → server marks is_seller=true).
class SellerQuestionDetailScreen extends ConsumerWidget {
  const SellerQuestionDetailScreen({required this.questionId, this.initial, super.key});

  final int questionId;
  final SellerQuestion? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final init = initial;
    return Scaffold(
      appBar: AppBar(title: Text('seller.question_title'.tr())),
      body: init != null
          ? _Thread(productId: init.productId, questionId: questionId)
          : ref.watch(sellerQuestionByIdProvider(questionId)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(child: Text('seller.error_generic'.tr())),
                data: (q) => q == null
                    ? Center(child: Text('seller.questions_empty_all'.tr()))
                    : _Thread(productId: q.productId, questionId: questionId),
              ),
    );
  }
}

class _Thread extends ConsumerWidget {
  const _Thread({required this.productId, required this.questionId});
  final int productId;
  final int questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final threadAsync =
        ref.watch(questionThreadProvider((productId, questionId)));
    return threadAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: TextButton(
          onPressed: () =>
              ref.invalidate(questionThreadProvider((productId, questionId))),
          child: Text('seller.error_generic'.tr()),
        ),
      ),
      data: (thread) {
        final q = thread.question;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(q.body, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${'seller.customer_label'.tr(namedArgs: {'id': '${q.userId}'})} · ${relativeTime(q.createdAt)}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => openAnswer(
                  context,
                  ref,
                  productId: productId,
                  questionId: questionId,
                ),
                icon: const Icon(Icons.reply_outlined, size: 18),
                label: Text('seller.answer_questions'.tr()),
              ),
            ),
            const SizedBox(height: 20),
            for (final (i, a) in thread.answers.indexed) ...[
              if (i > 0) const Divider(height: 24),
              AnswerRow(answer: a),
            ],
          ],
        );
      },
    );
  }
}
