import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/catalog/pdp/qa/answer_row.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_provider.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_submission.dart';

/// `/products/:id/questions/:qid` — a single question with its answers and an
/// "Yanıtla" CTA. Backed by [questionThreadProvider]; answering invalidates it
/// so the new answer appears.
class QuestionDetailScreen extends ConsumerWidget {
  const QuestionDetailScreen({
    required this.productId,
    required this.questionId,
    super.key,
  });

  final int productId;
  final int questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = ref.watch(questionThreadProvider((productId, questionId)));
    return Scaffold(
      appBar: AppBar(title: Text('qa.detail_title'.tr())),
      body: thread.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _ErrorRetry(
          onRetry: () => ref.invalidate(
            questionThreadProvider((productId, questionId)),
          ),
        ),
        data: (data) => _Body(
          productId: productId,
          questionId: questionId,
          thread: data,
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.productId,
    required this.questionId,
    required this.thread,
  });

  final int productId;
  final int questionId;
  final QuestionThread thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final q = thread.question;
    final date = DateFormat('dd.MM.yyyy').format(q.createdAt.toLocal());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Question block.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.help_outline_rounded, size: 22, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.body, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${q.authorName} · $date',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            label: Text('qa.answer_cta'.tr()),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.primary,
              side: BorderSide(color: cs.primary),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'qa.answers_header'.tr(),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (thread.answers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'qa.no_answers'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final (i, a) in thread.answers.indexed) ...[
            if (i > 0) const Divider(height: 24),
            AnswerRow(answer: a),
          ],
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('qa.load_error'.tr()),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: Text('common.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
