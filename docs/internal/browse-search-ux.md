# Browse/search UX — discovery (PLP-06 pills · PLP-10 inline category search · SE-10 refine)

Read-paths confirmed before building. **Headline discovery: zero backend, zero
codegen needed for all three** — the seams already exist end-to-end.

## The seams (all pre-existing)

- **`PlpFilters`** (`plp/plp_filters.dart`) already carries the one-tap toggles the
  quick pills need: `freeShippingOnly`, `inStock`, `priceDropped`, `ratingMin`.
  State lives in `plpFiltersProvider(plpKey)`; any change **rebuilds**
  `FilteredProductsNotifier` and refetches page 1 — pills are pure state writes.
- **Backend `GET /search` already accepts `category_id`**
  (`catalog_handlers.go: parseProductFilter(q, includeCategory=true)` →
  `ProductFilter.CategoryID`, commented "search-only") **plus the full filter set**
  (sort/min/max/brand/rating/free_shipping/in_stock/price_dropped/attr).
- **The generated client already exposes it**: `SearchApi.search({q, categoryId,
  …all filter params})` — the spec had it; no codegen.
- **`FilteredProductsNotifier`** (`filtered_products_provider.dart`) is a family on
  the category key; `build()` **watches** `plpFiltersProvider` — so any local field
  (e.g. an inline query) would be wiped on each filter change. The inline query must
  therefore live in its own watched provider (same lifecycle as filters).
- **Search screen** (`search_screen.dart`): a singleton `searchProvider`
  (`SearchNotifier`) holding `query`; filters piggyback on
  `plpFiltersProvider(plpKeyForSearch(query))`. The backend FTS is
  `plainto_tsquery` — **terms AND together**, so appending a refine term to the
  query *is* "search within results" server-side.

## Design

### PLP-06 — quick-filter pills (mobile)
`PlpQuickPills(plpKey)`: a horizontal `FilterChip` row — Ücretsiz Kargo
(`freeShippingOnly`), Stokta (`inStock`), Fiyatı Düşenler (`priceDropped`),
4★ ve üzeri (`ratingMin: 4` toggle). Mounted in `_buildMobile` between the result
count and the grid. **Mobile-only**: the wide layout already exposes these toggles
in the always-visible `FilterPanel` sidebar + active-chip row — duplicating them as
pills there adds noise, while on mobile the filters hide behind the sheet button, so
one-tap pills add real value. Labels reuse existing i18n (`plp.free_shipping`,
`catalog.filter_in_stock`, `plp.filter_price_dropped`, `plp.chip_rating`).

### PLP-10 — inline category search
A compact search field on the PLP ("Bu kategoride ara"). Query state:
`plpInlineQueryProvider` (`StateProvider.family<String, String>` keyed by plpKey, so
it survives notifier rebuilds and resets naturally per category).
`FilteredProductsNotifier.build` watches it; `_load` routes:
- query empty → `api.listProducts(categoryId, …)` (unchanged)
- query non-empty → `api.search(q: query, categoryId: _categoryId, …same filters)`
Same state shape, same pagination/pages, same `CatalogShell` — filters and sort keep
working *within* the scoped search because `/search` accepts the same params.

### SE-10 — search-within refine box
A compact "Sonuçlar içinde ara" field above the results grid in `SearchScreen`.
Submit appends the refine term to the active query (`setQuery('$query $term')`) —
`plainto_tsquery` AND-semantics narrows server-side; the header input syncs to show
the combined query; the refine field clears. No new state machinery.

## Discovery shifts
- **No backend work at all** — `/search?category_id=` existed (built for SE-06/SE-08
  era), and the generated Dart client already has `categoryId`. The audit's "reuse
  the search backend scoped to the category" assumption holds exactly.
- The inline query **cannot** be a notifier field (filter changes rebuild the family
  notifier) → it lives in `plpInlineQueryProvider`, mirroring the filters' lifecycle.
- SE-10 needs no results-side filtering: FTS AND-composition makes "append to query"
  the genuine narrow operation.
