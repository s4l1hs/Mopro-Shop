import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mopro/features/catalog/pdp/reviews/reviews_provider.dart';

/// Trendyol-style rating summary: a large average score with a "{N}
/// değerlendirme" caption on the left (60%) and five proportional rating bars on
/// the right (40%), 5★ → 1★ top to bottom. Renders an empty-state caption when
/// there are no reviews.
class RatingDistributionHistogram extends StatelessWidget {
  const RatingDistributionHistogram({required this.summary, super.key});

  final ReviewsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (summary.totalCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'reviews.empty'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        // Left 60%: average + count caption.
        Expanded(
          flex: 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                summary.average.toStringAsFixed(1),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'product.review_count'.tr(
                  namedArgs: {'count': '${summary.totalCount}'},
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // Right 40%: 5★ → 1★ bars.
        Expanded(
          flex: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var star = 5; star >= 1; star--)
                _BarRow(
                  star: star,
                  count: summary.distribution[star] ?? 0,
                  total: summary.totalCount,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.star,
    required this.count,
    required this.total,
  });

  final int star;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fraction = total == 0 ? 0.0 : count / total;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.star_rounded, size: 12, color: cs.primary),
          const SizedBox(width: 2),
          SizedBox(
            width: 10,
            child: Text(
              '$star',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(height: 4, color: cs.outlineVariant),
                  FractionallySizedBox(
                    widthFactor: fraction.clamp(0.0, 1.0),
                    child: Container(height: 4, color: cs.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
