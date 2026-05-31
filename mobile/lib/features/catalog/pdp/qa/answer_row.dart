import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/features/catalog/pdp/qa/qa_provider.dart';

/// A single answer in a question thread: author (with an optional "Satıcı"
/// badge), date, and the answer body.
class AnswerRow extends StatelessWidget {
  const AnswerRow({required this.answer, super.key});

  final Answer answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final date = DateFormat('dd.MM.yyyy').format(answer.createdAt.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              answer.authorName,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (answer.isSeller) ...[
              const SizedBox(width: 6),
              const _SellerBadge(),
            ],
            const SizedBox(width: 8),
            Text(
              date,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(answer.body, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _SellerBadge extends StatelessWidget {
  const _SellerBadge();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'qa.seller_badge'.tr(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.onPrimary,
        ),
      ),
    );
  }
}
