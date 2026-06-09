import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/core/di/providers.dart';
import 'package:mopro/core/network/app_error.dart';
import 'package:mopro/core/utils/debouncer.dart';
import 'package:mopro/core/utils/uri_ext.dart';
import 'package:mopro/core/widgets/error_banner.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/design/widgets/mopro_share_button.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_codec.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/plp/widgets/filter_panel.dart';
import 'package:mopro/features/catalog/plp/widgets/plp_filter_chips.dart';
import 'package:mopro/features/catalog/providers/filtered_products_provider.dart';
import 'package:mopro/features/catalog/widgets/filter_sheet.dart';
import 'package:mopro/features/catalog/widgets/sort_sheet.dart';
import 'package:mopro/features/growth/meta_tags_service.dart';
import 'package:mopro/features/growth/seo_head.dart';
import 'package:mopro/features/growth/structured_data_service.dart';
import 'package:mopro/widgets/catalog/catalog_shell.dart';
import 'package:mopro_api/mopro_api.dart';

class CategoryProductsScreen extends ConsumerStatefulWidget {
  const CategoryProductsScreen({
    required this.categoryId,
    required this.categoryName,
    super.key,
  });

  final int categoryId;
  final String categoryName;

  @override
  ConsumerState<CategoryProductsScreen> createState() =>
      _CategoryProductsScreenState();
}

class _CategoryProductsScreenState
    extends ConsumerState<CategoryProductsScreen> {
  static const _codec = PlpFiltersCodec();
  final _debouncer = Debouncer();
  bool _hydrated = false;

  String get _key => plpKeyForCategory(widget.categoryId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) return;
    _hydrated = true;
    // Hydrate filter state from the URL on entry (shareable/deep-linkable).
    // Read the route here (safe) but defer the provider mutation to after the
    // frame — modifying a provider during the build/dependencies phase throws.
    final params = GoRouterState.of(context).uri.queryParameters;
    final decoded = _codec.decode(params);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (decoded != ref.read(plpFiltersProvider(_key))) {
        ref.read(plpFiltersProvider(_key).notifier).set(decoded);
      }
    });
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  void _writeUrl(PlpFilters next) {
    _debouncer.run(() {
      if (!mounted) return;
      final q = _codec.encode(next);
      final base = GoRouterState.of(context).uri;
      // clearQueryParameters() is the safe clear — Uri.replace(queryParameters:
      // null) is a no-op (keeps the existing query). See lib/core/utils/uri_ext.
      final next0 =
          q.isEmpty ? base.clearQueryParameters() : base.replace(queryParameters: q);
      context.go(next0.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reflect PLP context in the browser tab title.
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(label: 'Mopro · ${widget.categoryName}'),
    );

    final filters = ref.watch(plpFiltersProvider(_key));
    // Mirror filter changes into the URL (debounced) from any source.
    ref.listen<PlpFilters>(plpFiltersProvider(_key), (_, next) => _writeUrl(next));

    final state = ref.watch(filteredProductsProvider(_key));
    final products = state.products.valueOrNull ?? [];
    final isLoading = state.products.isLoading;
    final hasError = state.products.hasError && products.isEmpty && !isLoading;

    if (hasError) {
      final err = state.products.error;
      final appError = err is AppError
          ? err
          : UnknownError(statusCode: 0, message: err.toString());
      return Scaffold(
        appBar: AppBar(title: Text(widget.categoryName)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorBanner(
            error: appError,
            onRetry: () =>
                ref.read(filteredProductsProvider(_key).notifier).refresh(),
          ),
        ),
      );
    }

    final shell = CatalogShell(
      products: products,
      isLoading: isLoading,
      hasMore: state.hasMore,
      loadingMore: state.loadingMore,
      loadMoreError: state.loadMoreError,
      onLoadMore: () =>
          ref.read(filteredProductsProvider(_key).notifier).loadMore(),
      currentSort: filters.sort.token,
      // Mobile shows the sticky sort/filter bar + bottom sheets; the wide
      // layout replaces them with the sidebar + chip row + sort dropdown, so
      // null these out there to hide CatalogShell's own bar.
      onSort: context.isMobile ? _showSortSheet : null,
      onFilter: context.isMobile ? _showFilterSheet : null,
      activeFilterCount: filters.activeChipCount,
      gridCrossAxisCount: context.isMobile ? 2 : (context.isDesktop ? 5 : 3),
      onRefresh: () async =>
          ref.read(filteredProductsProvider(_key).notifier).refresh(),
    );

    final webBase = ref.watch(webBaseUrlProvider);
    return SeoHead(
      meta: MetaTagsInput(
        title: '${widget.categoryName} — Mopro',
        description: 'seo.category_description'
            .tr(namedArgs: {'category': widget.categoryName}),
        canonicalUrl: '$webBase/categories/${widget.categoryId}',
      ),
      jsonLd: breadcrumbJsonLd([
        (name: 'Mopro', url: webBase),
        (
          name: widget.categoryName,
          url: '$webBase/categories/${widget.categoryId}',
        ),
      ]),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.categoryName),
          actions: [
            MoproShareButton(
              url: '$webBase/categories/${widget.categoryId}',
              title: widget.categoryName,
            ),
          ],
        ),
        body: context.isMobile ? shell : _buildWide(context, products, shell),
      ),
    );
  }

  // Tablet/desktop: sticky sidebar filter panel + (chip row + sort dropdown +
  // grid) (§2.1). The sidebar pins while the grid scrolls because it sits in a
  // separate, non-scrolling column.
  Widget _buildWide(
    BuildContext context,
    List<ProductSummary> products,
    Widget shell,
  ) {
    final sidebarW = context.isDesktop ? 280.0 : 260.0;
    final pad = context.isDesktop ? 32.0 : 24.0;
    final brands = products.map((p) => p.brand).toSet().toList()..sort();

    return LayoutBuilder(
      builder: (ctx, c) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: SizedBox(
              height: c.maxHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: sidebarW,
                      child: FilterPanel(
                        plpKey: _key,
                        currentCategoryId: widget.categoryId,
                        brands: brands,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: PlpFilterChips(plpKey: _key)),
                              _sortDropdown(),
                            ],
                          ),
                          Expanded(child: shell),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sortDropdown() {
    final current = ref.watch(plpFiltersProvider(_key)).sort;
    return PopupMenuButton<PlpSort>(
      initialValue: current,
      onSelected: (s) =>
          ref.read(plpFiltersProvider(_key).notifier).setSort(s),
      itemBuilder: (_) => [
        // All sorts render — `bestseller` is backed by real popularity (P-029).
        for (final s in PlpSort.values)
          PopupMenuItem<PlpSort>(
            value: s,
            child: Text('catalog.sort_${s.token}'.tr()),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('catalog.sort_${current.token}'.tr()),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Future<void> _showSortSheet() async {
    final filters = ref.read(plpFiltersProvider(_key));
    final selected = await showSortSheet(context, current: filters.sort.token);
    if (selected != null) {
      ref
          .read(plpFiltersProvider(_key).notifier)
          .setSort(PlpSort.fromToken(selected));
    }
  }

  Future<void> _showFilterSheet() async {
    // Brand facet sources its options from the loaded result set (distinct
    // brands) — same as the desktop sidebar (no aggregation endpoint yet).
    final products =
        ref.read(filteredProductsProvider(_key)).products.valueOrNull ?? [];
    final brands = products.map((p) => p.brand).toSet().toList()..sort();
    await showPlpFilterSheet(context, plpKey: _key, brands: brands);
  }
}
