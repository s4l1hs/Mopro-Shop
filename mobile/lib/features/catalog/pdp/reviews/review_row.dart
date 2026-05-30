import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/core/auth/auth_notifier.dart';
import 'package:mopro/core/auth/auth_state.dart';
import 'package:mopro/core/widgets/login_required_sheet.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/catalog/pdp/reviews/reviews_provider.dart';

/// A single review: star rating + date, optional title/body, and a "Faydalı (N)"
/// helpful-vote pill. Guests tapping the pill get the adaptive login presenter
/// (bottom sheet on mobile, dialog on desktop); authed users toggle optimistically.
class ReviewRow extends ConsumerWidget {
  const ReviewRow({required this.review, required this.productId, super.key});

  final Review review;
  final int productId;

  Future<void> _onHelpfulTap(BuildContext context, WidgetRef ref) async {
    final authed =
        ref.read(authNotifierProvider).valueOrNull is AuthAuthenticated;
    if (!authed) {
      requireAuth(
        context,
        ref,
        reason: 'reviews.login_to_vote'.tr(),
        onAuthed: () => ref
            .read(reviewsNotifierProvider(productId).notifier)
            .toggleHelpful(review.id),
      );
      return;
    }
    // Capture the messenger before the await so we don't touch context across
    // the async gap.
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(reviewsNotifierProvider(productId).notifier)
        .toggleHelpful(review.id);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('reviews.action_failed'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 5; i++)
              Icon(
                i < review.rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 16,
                color: i < review.rating
                    ? MoproTokens.ratingStar
                    : cs.outlineVariant,
              ),
            const SizedBox(width: 8),
            Text(
              review.createdAt.split('T').first,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (review.title.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            review.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (review.body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(review.body, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: _HelpfulButton(
            voted: review.votedByCurrentUser,
            count: review.helpfulCount,
            onTap: () => _onHelpfulTap(context, ref),
          ),
        ),
      ],
    );
  }
}

/// The "Faydalı (N)" pill. Voted → brand-orange filled (white content); not voted
/// → brand-orange outline. 32dp tall, fully rounded.
class _HelpfulButton extends StatelessWidget {
  const _HelpfulButton({
    required this.voted,
    required this.count,
    required this.onTap,
  });

  final bool voted;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = Text('reviews.helpful_count'.tr(namedArgs: {'count': '$count'}));
    const icon = Icon(Icons.thumb_up_alt_outlined, size: 16);

    return SizedBox(
      height: 32,
      child: voted
          ? FilledButton.icon(
              onPressed: onTap,
              icon: icon,
              label: label,
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                visualDensity: VisualDensity.compact,
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: icon,
              label: label,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                visualDensity: VisualDensity.compact,
              ),
            ),
    );
  }
}
