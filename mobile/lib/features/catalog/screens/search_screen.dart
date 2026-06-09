import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/responsive/responsive.dart';
import 'package:mopro/features/catalog/plp/plp_filters.dart';
import 'package:mopro/features/catalog/plp/plp_filters_provider.dart';
import 'package:mopro/features/catalog/plp/widgets/filter_panel.dart';
import 'package:mopro/features/catalog/plp/widgets/plp_filter_chips.dart';
import 'package:mopro/features/catalog/providers/categories_provider.dart';
import 'package:mopro/features/catalog/providers/recent_searches_provider.dart';
import 'package:mopro/features/catalog/providers/search_provider.dart';
import 'package:mopro/features/catalog/widgets/filter_sheet.dart';
import 'package:mopro/features/catalog/widgets/search_input.dart';
import 'package:mopro/features/catalog/widgets/sort_sheet.dart';
import 'package:mopro/widgets/catalog/catalog_shell.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final recent = ref.watch(recentSearchesProvider);

    // Reflect the search query in the browser tab title (§3.7).
    final query = _searchController.text.trim();
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: query.isEmpty
            ? 'Mopro · ${'router_title.search'.tr()}'
            : 'Mopro · ${'router_title.search_query'.tr(namedArgs: {'q': query})}',
      ),
    );

    // Filters live in plpFiltersProvider keyed by the query; this singleton
    // search provider doesn't watch them, so refetch when they change (P-026).
    final plpKey = plpKeyForSearch(query);
    ref.listen(plpFiltersProvider(plpKey), (prev, next) {
      if (prev != next) ref.read(searchProvider.notifier).reapplyFilters();
    });

    return Scaffold(
      appBar: AppBar(
        title: SearchInput(
          controller: _searchController,
          onChanged: (q) {
            ref.read(searchProvider.notifier).setQuery(q);
            if (q.trim().length > 1) {
              ref.read(recentSearchesProvider.notifier).add(q.trim());
            }
          },
          autofocus: true,
        ),
        titleSpacing: 0,
      ),
      body: state.isEmpty
          ? _EmptySearchBody(
              recent: recent,
              onSelectRecent: (q) {
                _searchController.text = q;
                ref.read(searchProvider.notifier).setQuery(q);
              },
            )
          : _results(context, state, query, plpKey),
    );
  }

  Widget _shell(SearchState state, String plpKey, {bool wide = false}) =>
      CatalogShell(
        products: state.results.valueOrNull ?? [],
        isLoading: state.results.isLoading,
        hasMore: state.hasMore,
        loadingMore: state.loadingMore,
        loadMoreError: state.loadMoreError,
        onLoadMore: () => ref.read(searchProvider.notifier).loadMore(),
        currentSort: ref.watch(plpFiltersProvider(plpKey)).sort.token,
        onSort: wide ? null : () => _showSortSheet(plpKey),
        // SE-02: mobile gets the filter sheet (was sort-only).
        onFilter: wide ? null : () => _showFilterSheet(plpKey, state),
        activeFilterCount: ref.watch(plpFiltersProvider(plpKey)).activeChipCount,
        // SE-05: responsive 2/3/4/5 grid. SE-04: mobile infinite scroll, desktop
        // numbered pages (CatalogShell already supports these).
        gridCrossAxisCount: _gridColumns(context),
        infiniteScroll: !wide,
        currentPage: state.page,
        totalPages: state.totalPages,
        onGoToPage:
            wide ? (p) => ref.read(searchProvider.notifier).goToPage(p) : null,
      );

  // SE-05: mirror the PLP breakpoints — 2 (mobile) / 3 (tablet) / 4 (desktop
  // <1440) / 5 (ultra-wide).
  int _gridColumns(BuildContext context) {
    if (context.isMobile) return 2;
    if (!context.isDesktop) return 3;
    return MediaQuery.sizeOf(context).width >= 1440 ? 5 : 4;
  }

  // SE-02: brands are the distinct brands of the loaded results (mirrors PLP).
  Future<void> _showFilterSheet(String plpKey, SearchState state) async {
    final products = state.results.valueOrNull ?? [];
    final brands = products.map((p) => p.brand).toSet().toList()..sort();
    await showPlpFilterSheet(context, plpKey: plpKey, brands: brands);
  }

  Widget _results(
    BuildContext context,
    SearchState state,
    String query,
    String plpKey,
  ) {
    if (context.isMobile) {
      // SE-03: result count above the grid (rendered only when total lands).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.total != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: _ResultCount(total: state.total!),
            ),
          Expanded(child: _shell(state, plpKey)),
        ],
      );
    }

    // Tablet/desktop: FilterPanel sidebar (no category tree) + a query chip +
    // filter chips + the results grid. Filters write plpFiltersProvider keyed by
    // the query; SearchScreen.build refetches on change (P-026 wiring).
    final sidebarW = context.isDesktop ? 280.0 : 260.0;
    final pad = context.isDesktop ? 32.0 : 24.0;

    return LayoutBuilder(
      builder: (ctx, c) => Center(
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
                      plpKey: plpKey,
                      currentCategoryId: -1,
                      showCategoryTree: false,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Chip(
                                avatar: const Icon(Icons.search, size: 16),
                                label: Text('"$query"'),
                              ),
                            ),
                            // SE-03: result count next to the query chip.
                            if (state.total != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _ResultCount(total: state.total!),
                              ),
                            Expanded(child: PlpFilterChips(plpKey: plpKey)),
                          ],
                        ),
                        Expanded(child: _shell(state, plpKey, wide: true)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSortSheet(String plpKey) async {
    final current = ref.read(plpFiltersProvider(plpKey)).sort.token;
    final selected = await showSortSheet(context, current: current);
    if (selected != null && selected != current) {
      ref
          .read(plpFiltersProvider(plpKey).notifier)
          .setSort(PlpSort.fromToken(selected));
    }
  }
}

/// Search result count (SE-03) — "N ürün". Reuses the PLP `plp.result_count`
/// key. Rendered only when `SearchState.total` is present.
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Text(
      'plp.result_count'.tr(args: ['$total']),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class _EmptySearchBody extends ConsumerWidget {
  const _EmptySearchBody({
    required this.recent,
    required this.onSelectRecent,
  });

  final List<String> recent;
  final ValueChanged<String> onSelectRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recent.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'search.recent_searches'.tr(),
                  style: theme.textTheme.titleSmall,
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(recentSearchesProvider.notifier).clear(),
                  child: Text('search.clear_recent'.tr()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: recent
                  .map(
                    (q) => InputChip(
                      label: Text(q),
                      onPressed: () => onSelectRecent(q),
                      onDeleted: () =>
                          ref.read(recentSearchesProvider.notifier).remove(q),
                      deleteIcon: const Icon(Icons.close, size: 14),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],
          const _CategorySuggestions(),
        ],
      ),
    );
  }
}

class _CategorySuggestions extends ConsumerWidget {
  const _CategorySuggestions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categoriesState = ref.watch(categoriesProvider);

    return categoriesState.categories.maybeWhen(
      data: (cats) {
        final roots = cats.where((c) => c.parentId == null).take(8).toList();
        if (roots.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'search.suggested_categories'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: roots
                  .map(
                    (cat) => ActionChip(
                      label: Text(cat.name),
                      onPressed: () => context.push(
                        '/categories/${cat.id}',
                        extra: cat.name,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
