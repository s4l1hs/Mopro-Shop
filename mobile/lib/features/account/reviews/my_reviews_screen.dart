import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/tokens.dart';
import 'package:mopro/features/account/widgets/account_chrome_scope.dart';
import 'package:mopro/features/catalog/pdp/reviews/review_submission.dart';
import 'package:mopro/features/catalog/pdp/reviews/review_write_provider.dart';

/// `/account/reviews` — the current user's own reviews with inline edit and
/// delete. Reuses [openReviewForm] for editing; delete is optimistic with a
/// confirmation dialog and SnackBar rollback feedback.
class MyReviewsScreen extends ConsumerWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myReviewsProvider);
    final notifier = ref.read(myReviewsProvider.notifier);

    final Widget body;
    if (state.loading && state.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.error != null && state.items.isEmpty) {
      body = _ErrorRetry(onRetry: notifier.refresh);
    } else if (state.items.isEmpty) {
      body = _Empty(onGoShopping: () => context.go('/'));
    } else {
      body = RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: state.items.length + (state.hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            if (i >= state.items.length) {
              return _LoadMore(
                loading: state.loadingMore,
                onTap: notifier.loadMore,
              );
            }
            return _MyReviewCard(review: state.items[i]);
          },
        ),
      );
    }

    return Scaffold(
      appBar: AccountChromeScope.suppressed(context)
          ? null
          : AppBar(title: Text('reviews.my_title'.tr())),
      body: body,
    );
  }
}

class _MyReviewCard extends ConsumerWidget {
  const _MyReviewCard({required this.review});

  final UserReview review;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('reviews.delete_confirm_title'.tr()),
        content: Text('reviews.delete_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    final ok = await ref
        .read(myReviewsProvider.notifier)
        .delete(review.productId, review.id);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('reviews.delete_failed'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: review.productThumbnail.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: review.productThumbnail,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _thumb(cs),
                      )
                    : _thumb(cs),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => context.go('/products/${review.productId}'),
                  child: Text(
                    review.productTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => openReviewForm(
                  context,
                  ref,
                  productId: review.productId,
                  reviewId: review.id,
                  initialRating: review.rating,
                  initialTitle: review.title,
                  initialBody: review.body,
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text('reviews.edit'.tr()),
                style: TextButton.styleFrom(foregroundColor: cs.primary),
              ),
              TextButton.icon(
                onPressed: () => _confirmDelete(context, ref),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text('common.delete'.tr()),
                style: TextButton.styleFrom(foregroundColor: cs.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumb(ColorScheme cs) => Container(
        width: 48,
        height: 48,
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.image_outlined, size: 24, color: cs.outlineVariant),
      );
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: loading ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.primary),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: loading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              )
            : Text('reviews.load_more'.tr()),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onGoShopping});

  final VoidCallback onGoShopping;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.rate_review_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('reviews.my_empty'.tr(), style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onGoShopping,
              child: Text('reviews.go_shopping'.tr()),
            ),
          ],
        ),
      ),
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
            Text('reviews.load_error'.tr()),
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
