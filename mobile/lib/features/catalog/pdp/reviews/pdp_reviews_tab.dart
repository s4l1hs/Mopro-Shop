import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mopro/features/catalog/pdp/reviews/rating_distribution_histogram.dart';
import 'package:mopro/features/catalog/pdp/reviews/review_row.dart';
import 'package:mopro/features/catalog/pdp/reviews/reviews_provider.dart';

/// The product detail page "Değerlendirmeler" tab: rating histogram, a sort
/// dropdown, the paginated review list with helpful-vote buttons, and a
/// "Daha fazla" pagination button. [scrollable] is true inside the narrow
/// TabBarView (own ListView) and false inside the wide layout's outer scroll
/// (renders as a Column).
class PdpReviewsTab extends ConsumerWidget {
  const PdpReviewsTab({
    required this.productId,
    this.scrollable = true,
    super.key,
  });

  final int productId;
  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final state = ref.watch(reviewsNotifierProvider(productId));
    final notifier = ref.read(reviewsNotifierProvider(productId).notifier);

    // Initial load: skeleton placeholder.
    if (state.loading && state.items.isEmpty && state.summary == null) {
      return _wrap(const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ]);
    }

    // Initial load failure: caption + retry.
    if (state.error != null && state.items.isEmpty) {
      return _wrap([
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'reviews.load_error'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => notifier.setSort(state.sort),
                child: Text('common.retry'.tr()),
              ),
            ],
          ),
        ),
      ]);
    }

    final children = <Widget>[
      if (state.summary != null)
        RatingDistributionHistogram(summary: state.summary!),
      const SizedBox(height: 24),
      Row(
        children: [
          Expanded(
            child: Text(
              'reviews.header'.tr(namedArgs: {'count': '${state.total}'}),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _SortMenu(current: state.sort, onSelected: notifier.setSort),
        ],
      ),
      const SizedBox(height: 8),
      for (final r in state.items) ...[
        ReviewRow(review: r, productId: productId),
        const SizedBox(height: 16),
      ],
      if (state.hasMore)
        _LoadMoreButton(
          loading: state.loadingMore,
          onTap: notifier.loadMore,
        ),
    ];

    return _wrap(children);
  }

  Widget _wrap(List<Widget> children) {
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 16);
    if (scrollable) {
      return ListView(padding: padding, children: children);
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// Sort dropdown — a PopupMenuButton (matches the 5b PLP sort deviation).
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.current, required this.onSelected});

  final ReviewSort current;
  final ValueChanged<ReviewSort> onSelected;

  static String _key(ReviewSort s) => switch (s) {
        ReviewSort.newest => 'reviews.sort_newest',
        ReviewSort.highest => 'reviews.sort_highest',
        ReviewSort.lowest => 'reviews.sort_lowest',
        ReviewSort.helpful => 'reviews.sort_helpful',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<ReviewSort>(
      initialValue: current,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final s in ReviewSort.values)
          PopupMenuItem<ReviewSort>(
            value: s,
            child: Text(_key(s).tr()),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _key(current).tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Icon(Icons.arrow_drop_down, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

/// Full-width brand-orange outline pagination button; shows a spinner and
/// disables while the next page loads.
class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({required this.loading, required this.onTap});

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
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('reviews.load_more'.tr()),
                ],
              )
            : Text('reviews.load_more'.tr()),
      ),
    );
  }
}
