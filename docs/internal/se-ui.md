# Search UI Completion (SE-UI) — Session 1 — discovery

> Port the PLP screen-level wins `SearchScreen` missed + search-specific UI.
> Parallel with Session 2 (backend). Verified on `feat/search-ui-completion`.

## Ownership / coordination reality

- **Discovery shift:** the prompt says this session owns `lib/features/search/**`,
  but **there is no such directory** — search lives in
  `lib/features/catalog/screens/search_screen.dart`,
  `…/providers/search_provider.dart`, `…/widgets/search_input.dart`,
  `…/providers/recent_searches_provider.dart`, and `lib/shell/{search_suggestions_
  dropdown,web_search_pill,header_search_bar}.dart`. **None overlaps Session 2's
  forbidden set** (`api/openapi.yaml`, generated clients, `internal/catalog/**`,
  `plp/widgets/filter_panel.dart`) — so I edit the Dart search files freely and
  only **mount** the shared `FilterPanel`/`CatalogShell` (no internals touched).

## What's UI-only vs needs backend

| SE | UI-only? | Notes |
|---|---|---|
| **SE-02** mobile filter | ✅ | `_shell` sets `onSort` but not `onFilter` → wire `onFilter` → `showPlpFilterSheet(plpKey, brands-from-results)` (the PLP-01 sheet). |
| **SE-03** result count | ✅ | The search response **already carries `pagination.total`** (`api.search` → `ListProducts200Response`); `SearchState` just discards it. Add `total` (nullable, per the handshake) + render. *No Session-2 dependency for the field; guarded anyway.* |
| **SE-04** pagination | ✅ | `pagination.totalPages` is also in the response. Add `totalPages` + `goToPage(n)` (replace-load) to the provider; mount `CatalogShell` with `infiniteScroll: isMobile` + `onGoToPage`/`currentPage`/`totalPages` — **`CatalogShell` already supports these** (PLP-03/15 work). |
| **SE-05** grid 2/3/4/5 | ✅ | port `_gridColumns` (mirror `CategoryProductsScreen`); search uses flat `wide ? 5/3 : 2`. |
| **SE-06** brand/product autocomplete | ⚠ split | `/search/suggest` exists (`searchSuggest` → `List<String>` query completions) but is **unused** → wire it (query completions). **Brand + product (structured) suggestions need a new backend surface → flag for Session 2 / DEFER.** |
| **SE-07** no-results recovery | ⚠ split | trending (`trendingSearchesProvider`) + categories available → build the recovery UI. **"Did you mean" / spelling correction needs backend → flag / DEFER.** |
| **SE-09** mobile empty trending | ✅ | `trendingSearchesProvider` available → add a trending section to `_EmptySearchBody`. |

## Shared-body extraction

§1 recommends one shared results body for PLP + Search. But adopting it in PLP
means editing `CategoryProductsScreen`, and the directive is "keep all edits
within search/new-shared-widget files." → **I port the wins *into* `SearchScreen`
directly** (mirroring the PLP wiring) rather than refactor the PLP screen. Noted
as a future cleanup (a shared `PlpResultsBody` both render) — out of scope to keep
the parallel sessions conflict-free.

## Plan (PRs)

- **PR 1 — ports (SE-02/03/04/05), all UI-only:** `SearchState.total`+`totalPages`,
  `SearchNotifier.goToPage` + a `replace` load; `SearchScreen` wires the filter
  sheet, the count, `infiniteScroll`/numbered-pages, and `_gridColumns`. Tests +
  goldens.
- **PR 2 — search-specific (SE-06/07/09):** wire `searchSuggest` query
  completions into the dropdown + mobile; no-results recovery (trending +
  categories); mobile-empty trending. **Flag for Session 2:** brand/product
  structured suggestions (SE-06), "did you mean" (SE-07). DEFER those.
