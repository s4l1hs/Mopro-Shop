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
    this.onRefresh,
    this.gridCrossAxisCount = 2,
    this.infiniteScroll = false,
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
  final Future<void> Function()? onRefresh;
  final int gridCrossAxisCount;

  /// When true (mobile), the next page auto-loads as the user nears the bottom
  /// and the "load more" button is hidden. Desktop keeps the explicit button.
  final bool infiniteScroll;

  /// Trigger the next page when the user scrolls within this many px of the end.
  static const double _loadMoreThreshold = 150;

  @override
  Widget build(BuildContext context) {
    final body = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (onSort != null || onFilter != null)
          SliverToBoxAdapter(
            child: _FilterSortBar(
              currentSort: currentSort,
              activeFilterCount: activeFilterCount,
              onSort: onSort,
              onFilter: onFilter,
            ),
          ),
        if (isLoading)
          const SliverPadding(
            padding: EdgeInsets.all(12),
            sliver: _SkeletonGrid(),
          )
        else if (products.isEmpty)
          SliverToBoxAdapter(child: EmptyState.empty())
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
            child: _LoadMoreSection(
              hasMore: hasMore,
              loadingMore: loadingMore,
              loadMoreError: loadMoreError,
              onLoadMore: onLoadMore,
              // Mobile auto-loads via scroll → no button; spinner/error stay.
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
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
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
