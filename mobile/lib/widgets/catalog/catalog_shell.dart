import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/widgets/empty_state.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/features/catalog/widgets/product_card.dart';
import 'package:mopro/features/catalog/widgets/product_grid.dart';
import 'package:mopro_api/mopro_api.dart';

class CatalogShell extends StatelessWidget {
  const CatalogShell({
    required this.products,
    required this.isLoading,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
    this.loadMoreError,
    this.currentSort,
    this.onSort,
    this.onFilter,
    this.activeFilterCount = 0,
    this.onClearFilters,
    this.onRefresh,
    this.gridCrossAxisCount = 2,
    this.infiniteScroll = false,
    this.currentPage = 1,
    this.totalPages = 1,
    this.onGoToPage,
    super.key,
  });

  final List<ProductSummary> products;
  final bool isLoading;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  final AppError? loadMoreError;
  final String? currentSort;
  final VoidCallback? onSort;
  final VoidCallback? onFilter;
  final int activeFilterCount;

  /// PLP-08: when the empty result is caused by active filters, the no-results
  /// state shows a "clear filters" CTA wired to this. Null → bare empty state.
  final VoidCallback? onClearFilters;

  final Future<void> Function()? onRefresh;
  final int gridCrossAxisCount;

  /// When true (mobile), the next page auto-loads as the user nears the bottom
  /// and the "load more" button is hidden. Desktop keeps the explicit button.
  final bool infiniteScroll;

  /// Desktop numbered-pages control (PLP-15): the active page, the page count,
  /// and the jump callback. Used only when `!infiniteScroll`.
  final int currentPage;
  final int totalPages;
  final ValueChanged<int>? onGoToPage;

  /// Trigger the next page when the user scrolls within this many px of the end.
  static const double _loadMoreThreshold = 150;

  @override
  Widget build(BuildContext context) {
    final body = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (onSort != null || onFilter != null)
          // PLP-20: pin the mobile sort/filter bar so it stays in reach on scroll.
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedBarDelegate(
              _FilterSortBar(
                currentSort: currentSort,
                activeFilterCount: activeFilterCount,
                onSort: onSort,
                onFilter: onFilter,
              ),
            ),
          ),
        if (isLoading)
          const SliverPadding(
            padding: EdgeInsets.all(12),
            sliver: _SkeletonGrid(),
          )
        else if (products.isEmpty)
          SliverToBoxAdapter(
            // PLP-08: if filters are what emptied the grid, offer "clear filters".
            child: (activeFilterCount > 0 && onClearFilters != null)
                ? EmptyState.filtered(onAction: onClearFilters!)
                : EmptyState.empty(),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: ProductGrid(
              products: products,
              crossAxisCount: gridCrossAxisCount,
              onProductTap: (p) => context.push('/products/${p.id}'),
            ),
          ),
        if (!isLoading)
          SliverToBoxAdapter(
            // Mobile = infinite scroll (no button; spinner/error stay). Desktop =
            // numbered pages (PLP-15) when there's more than one page.
            child: !infiniteScroll && onGoToPage != null
                ? (totalPages > 1
                    ? _NumberedPages(
                        currentPage: currentPage,
                        totalPages: totalPages,
                        onGoToPage: onGoToPage!,
                      )
                    : const SizedBox.shrink())
                : _LoadMoreSection(
                    hasMore: hasMore,
                    loadingMore: loadingMore,
                    loadMoreError: loadMoreError,
                    onLoadMore: onLoadMore,
                    showButton: !infiniteScroll,
                  ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );

    // Infinite scroll (mobile): fetch page N+1 within _loadMoreThreshold px of
    // the bottom. `loadMore()` is synchronously guarded (sets loadingMore before
    // its await) so repeated notifications can't double-fetch.
    var content = infiniteScroll
        ? NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (hasMore &&
                  !loadingMore &&
                  n.metrics.axis == Axis.vertical &&
                  n.metrics.pixels >=
                      n.metrics.maxScrollExtent - _loadMoreThreshold) {
                onLoadMore();
              }
              return false;
            },
            child: body,
          )
        : body;

    if (onRefresh != null) {
      content = RefreshIndicator(onRefresh: onRefresh!, child: content);
    }
    return content;
  }
}

class _FilterSortBar extends StatelessWidget {
  const _FilterSortBar({
    this.currentSort,
    this.activeFilterCount = 0,
    this.onSort,
    this.onFilter,
  });

  final String? currentSort;
  final int activeFilterCount;
  final VoidCallback? onSort;
  final VoidCallback? onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        // Opaque so scrolled content doesn't show through when pinned (PLP-20).
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (onFilter != null)
            _BarButton(
              icon: Icons.tune,
              label: 'catalog.filter_title'.tr(),
              badge: activeFilterCount > 0 ? activeFilterCount : null,
              onTap: onFilter!,
            ),
          if (onFilter != null && onSort != null)
            VerticalDivider(
              width: 16,
              indent: 10,
              endIndent: 10,
              color: colorScheme.outlineVariant,
            ),
          if (onSort != null)
            _BarButton(
              icon: Icons.sort,
              label: _sortLabel(currentSort),
              onTap: onSort!,
            ),
          const Spacer(),
        ],
      ),
    );
  }

  String _sortLabel(String? sort) => switch (sort) {
        'bestseller' => 'catalog.sort_bestseller'.tr(),
        'newest' => 'catalog.sort_newest'.tr(),
        'price_asc' => 'catalog.sort_price_asc'.tr(),
        'price_desc' => 'catalog.sort_price_desc'.tr(),
        'cashback_desc' => 'catalog.sort_cashback_desc'.tr(),
        _ => 'catalog.sort_recommended'.tr(),
      };
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.onSurface),
                if (badge != null)
                  Positioned(
                    top: -5,
                    right: -5,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$badge',
                          style: TextStyle(
                            color: theme.colorScheme.onError,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        // Lockstep with ProductGrid so the skeleton→loaded swap doesn't shift.
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.68,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => const SkeletonProductCard(),
    );
  }
}

class _LoadMoreSection extends StatelessWidget {
  const _LoadMoreSection({
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
    this.loadMoreError,
    this.showButton = true,
  });

  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  final AppError? loadMoreError;
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    if (loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorBanner(error: loadMoreError!, onRetry: onLoadMore),
      );
    }
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (hasMore && showButton) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: OutlinedButton(
            onPressed: onLoadMore,
            child: Text('catalog.load_more'.tr()),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Desktop numbered-pages control (PLP-15): `‹ 1 … 4 [5] 6 … 20 ›`. The active
/// page uses the brand token; ends are always shown with `…` gaps.
class _NumberedPages extends StatelessWidget {
  const _NumberedPages({
    required this.currentPage,
    required this.totalPages,
    required this.onGoToPage,
  });

  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onGoToPage;

  /// Page numbers to render, with `null` marking an ellipsis gap. Always shows
  /// the first + last page and a ±1 window around the current page.
  static List<int?> _window(int current, int total) {
    if (total <= 7) return [for (var i = 1; i <= total; i++) i];
    final keep = <int>{1, total};
    for (var i = current - 1; i <= current + 1; i++) {
      if (i >= 1 && i <= total) keep.add(i);
    }
    final sorted = keep.toList()..sort();
    final out = <int?>[];
    int? prev;
    for (final p in sorted) {
      if (prev != null && p - prev > 1) out.add(null);
      out.add(p);
      prev = p;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _arrow(
            Icons.chevron_left,
            currentPage > 1 ? () => onGoToPage(currentPage - 1) : null,
            cs,
          ),
          for (final p in _window(currentPage, totalPages))
            if (p == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('…'),
              )
            else
              _PageButton(
                key: ValueKey('plp-page-$p'),
                page: p,
                selected: p == currentPage,
                onTap: () => onGoToPage(p),
              ),
          _arrow(
            Icons.chevron_right,
            currentPage < totalPages ? () => onGoToPage(currentPage + 1) : null,
            cs,
          ),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback? onTap, ColorScheme cs) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        visualDensity: VisualDensity.compact,
        color: cs.onSurface,
        disabledColor: cs.outlineVariant,
      );
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.page,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? cs.primary : null,
            borderRadius: BorderRadius.circular(6),
            border: selected ? null : Border.all(color: cs.outlineVariant),
          ),
          child: Text(
            '$page',
            style: TextStyle(
              color: selected ? cs.onPrimary : cs.onSurface,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pins the mobile sort/filter bar at the top of the scroll view (PLP-20). Fixed
/// 48dp; rebuilds when the (already-rebuilt) [child] changes (sort/count).
class _PinnedBarDelegate extends SliverPersistentHeaderDelegate {
  _PinnedBarDelegate(this.child);

  final Widget child;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(_PinnedBarDelegate oldDelegate) => oldDelegate.child != child;
}
