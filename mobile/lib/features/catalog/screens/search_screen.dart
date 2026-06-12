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
import 'package:mopro/features/catalog/providers/home_provider.dart'
    show trendingSearchesProvider;
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
          ? _EmptySearchBody(recent: recent, onSelectQuery: _applyQuery)
          // SE-07: a query that returned nothing gets a recovery body (trending +
          // categories) instead of a bare empty state.
          : _isNoResults(state)
              ? _NoResultsBody(query: query, onSelectQuery: _applyQuery)
              : _results(context, state, query, plpKey),
    );
  }

  void _applyQuery(String q) {
    _searchController.text = q;
    ref.read(searchProvider.notifier).setQuery(q);
  }

  bool _isNoResults(SearchState state) =>
      state.results.maybeWhen(data: (r) => r.isEmpty, orElse: () => false);

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
          // SE-10: refine box — appending the term to the query narrows
          // server-side (plainto_tsquery ANDs terms).
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: _RefineBox(
              onRefine: (term) => _applyQuery('$query $term'),
            ),
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
                            // SE-10: refine within results.
                            SizedBox(
                              width: 240,
                              child: _RefineBox(
                                onRefine: (term) =>
                                    _applyQuery('$query $term'),
                              ),
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
    required this.onSelectQuery,
  });

  final List<String> recent;
  final ValueChanged<String> onSelectQuery;

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
                      onPressed: () => onSelectQuery(q),
                      onDeleted: () =>
                          ref.read(recentSearchesProvider.notifier).remove(q),
                      deleteIcon: const Icon(Icons.close, size: 14),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],
          // SE-09: trending on the mobile empty state (parity with the desktop
          // dropdown, which already shows trending).
          _TrendingChips(onSelectQuery: onSelectQuery),
          const _CategorySuggestions(),
        ],
      ),
    );
  }
}

/// Trending searches as tappable chips (SE-09 / SE-07). Renders nothing until
/// `trendingSearchesProvider` has data.
class _TrendingChips extends ConsumerWidget {
  const _TrendingChips({required this.onSelectQuery});

  final ValueChanged<String> onSelectQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trending = ref.watch(trendingSearchesProvider);
    final terms = trending.valueOrNull ?? const <String>[];
    if (terms.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('search.trending'.tr(), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: terms
              .map(
                (q) => ActionChip(
                  avatar: const Icon(Icons.trending_up, size: 16),
                  label: Text(q),
                  onPressed: () => onSelectQuery(q),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// SE-07: no-results recovery — the query echo + trending + category shortcuts so
/// a dead-end query still offers a way forward. "Did you mean"/spelling
/// correction is NOT built here — it needs a backend suggest-correction surface
/// (flagged for Session 2 / DEFER).
class _NoResultsBody extends StatelessWidget {
  const _NoResultsBody({required this.query, required this.onSelectQuery});

  final String query;
  final ValueChanged<String> onSelectQuery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          // Query echo + the shared empty message (reuses existing keys — no new
          // i18n). A query-specific "X için sonuç yok" string + "did you mean"
          // are deferred (the latter needs a backend correction surface).
          Text('"$query"', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'empty_state.empty_message'.tr(),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _TrendingChips(onSelectQuery: onSelectQuery),
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

/// SE-10: "search within results" refine box. Submitting appends the term to
/// the active query (the FTS backend ANDs terms → genuine server-side
/// narrowing); the header input syncs to the combined query and this field
/// clears for the next refinement.
class _RefineBox extends StatefulWidget {
  const _RefineBox({required this.onRefine});

  final ValueChanged<String> onRefine;

  @override
  State<_RefineBox> createState() => _RefineBoxState();
}

class _RefineBoxState extends State<_RefineBox> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final term = raw.trim();
    if (term.isEmpty) return;
    _controller.clear();
    widget.onRefine(term);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: TextField(
        key: const ValueKey('se10-refine'),
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'search.refine_hint'.tr(),
          prefixIcon:
              Icon(Icons.manage_search, size: 18, color: cs.onSurfaceVariant),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
