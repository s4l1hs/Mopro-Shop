# P-026 Discovery — Wire inert search/PLP filters

> Discovery pass for `PARITY_AUDIT P-026` (search/PLP filters render but are inert).
> Per the PR prompt §1.3, the backend-reality check is the scope-shaper. This doc is
> the deliverable for commit 1 and determines whether the PR proceeds to wiring.

## Outcome: **C — BLOCKED-BY-BACKEND-GAP**

The filter **frontend is fully built** — state model, URL codec, desktop sidebar panel,
mobile bottom sheet, active-filter chips, clear-all, and a debounced URL mirror all
exist and correctly write filter state. The single missing link is the **backend**:
the `/products` and `/search` endpoints (handler → service → repository) apply **no
filter dimension at all**, and do not even honor the `sort` param they declare in the
OpenAPI spec. No filter dimension (price / brand / rating / free-shipping) — nor sort —
can be made functional end-to-end without backend work, so **no frontend wiring ships
in this PR**. The gap is filed as new finding **P-028 (HIGH, backend)**; P-026 is closed
as `BLOCKED-BY-BACKEND-GAP` pending it.

This matches the audit's own P-026 note (`TRENDYOL_PARITY_AUDIT.md:122`): *"Backend
dependency: the catalog/search API must accept the filter params."* Discovery confirms
it does not.

---

## §1 — Filter UI inventory (what renders)

| File | LOC | Shape | Mounted by |
|---|---|---|---|
| `catalog/plp/widgets/filter_panel.dart` | 377 | Desktop/tablet sidebar (brand / price / rating / shipping + category tree) | PLP `category_products_screen.dart:197`; search `search_screen.dart:110` (no tree) |
| `catalog/widgets/filter_sheet.dart` | 239 | Mobile modal bottom sheet (price / shipping / in-stock / cashback-only) | PLP `category_products_screen.dart:263` (`_showFilterSheet`) |
| `catalog/plp/widgets/plp_filter_chips.dart` | 86 | Active-filter chip row (remove-on-tap) | PLP `:209`; search `:132` |
| `catalog/widgets/sort_sheet.dart` | 71 | Mobile sort options sheet | PLP `:253`; search `:148` |
| `catalog/plp/plp_filters.dart` | 122 | `PlpFilters` immutable state + `PlpSort` enum | — (substrate) |
| `catalog/plp/plp_filters_codec.dart` | — | URL query ⇄ `PlpFilters` round-trip | `category_products_screen.dart:44,59,77` |
| `catalog/plp/plp_filters_provider.dart` | 37 | `plpFiltersProvider` family (key = `'<catId>'` or `'_search:<q>'`) | all of the above |

Both screens render the filter UI on tablet/desktop (sidebar) and mobile (sheet), and
both persist selections to `plpFiltersProvider` + the URL. **The controls work as
controls** — they update state, the chips reflect it, the URL mirrors it, the
active-count badge increments (`category_products_screen.dart:135`). What does not
happen is a re-query that honors the selection.

---

## §2 — Filter dimensions enumerated

Two **divergent** state models feed the same `plpFiltersProvider`:

**Desktop `FilterPanel` → `PlpFilters`** (`plp_filters.dart:36-53`):

| Dimension | UI pattern | State field | Would send |
|---|---|---|---|
| Sort | dropdown / sheet | `sort` (`PlpSort`) | `sort=<token>` |
| Price range | range slider + min/max fields | `priceMinMinor` / `priceMaxMinor` | `min_price` / `max_price` |
| Brand | multi-select checkboxes (searchable) | `brands: List<String>` | `brand=` (repeat?) |
| Rating | single-select radio (4★/3★/2★ & up) | `ratingMin: int?` | `rating_min=` |
| Free shipping | toggle | `freeShippingOnly: bool` | `free_shipping=true` |

**Mobile `FilterSheet` → `ProductFilterOptions`** (`filter_sheet.dart:4-17`):

| Dimension | UI pattern | Bridged to `PlpFilters`? |
|---|---|---|
| Price range | min/max fields | yes (`category_products_screen.dart:274-275`) |
| Free shipping | toggle | yes (`:276`) |
| In-stock only | toggle | **no** — `PlpFilters` has no field → dropped on bridge |
| Cashback only | toggle | **no** — dropped on bridge |

> The mobile sheet has `in_stock` + `cashback_only` toggles that the desktop panel
> lacks, and lacks the brand + rating the desktop panel has. This frontend divergence
> is a secondary observation (§8), **not** part of P-026 (which is inert→functional).

---

## §3 — Backend-reality check (the decision)

Traced each dimension through all six layers. `✓` = present/applied, `✗` = absent/ignored.

### `/products` (PLP) — `CatalogApi.listProducts` → `handleListProducts`

| Layer | Evidence | sort | price | brand | rating | shipping |
|---|---|:--:|:--:|:--:|:--:|:--:|
| OpenAPI spec | `openapi.yaml:700-734` | ✓ | ✗ | ✗ | ✗ | ✗ |
| Generated client | `catalog_api.dart:396-434` | ✓ | ✗ | ✗ | ✗ | ✗ |
| Provider (sends) | `filtered_products_provider.dart:48-52` | ✓ | ✗ | ✗ | ✗ | ✗ |
| **Handler (reads)** | `catalog_handlers.go:53-88` | **✗** | ✗ | ✗ | ✗ | ✗ |
| Service | `internal/catalog/api.go:30` | ✗ | ✗ | ✗ | ✗ | ✗ |
| Repository | `internal/catalog/repository.go:307` | ✗ | ✗ | ✗ | ✗ | ✗ |

`handleListProducts` reads only `category_id`, `page`, `per_page`, `market` and calls
`svc.ListProductsByCategory(ctx, categoryID, locale, market, page, perPage)` — **no sort
argument exists in the signature.** The client sends `?sort=…`; the handler drops it.

### `/search` — `SearchApi.search` → `handleSearch`

| Layer | Evidence | sort | price (min/max) | category | brand | rating | shipping |
|---|---|:--:|:--:|:--:|:--:|:--:|:--:|
| OpenAPI spec ("with filters") | `openapi.yaml:894-948` | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| Generated client | `search_api.dart:44-85` | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| Provider (sends) | `search_provider.dart:85` (`api.search(q:, page:)`) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **Handler (reads)** | `catalog_handlers.go:90-121` | **✗** | **✗** | **✗** | ✗ | ✗ | ✗ |
| Service | `internal/catalog/api.go:31` (`SearchSummary`) | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Repository | `internal/catalog/repository.go` | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

The `/search` **spec + generated client already support `min_price`, `max_price`,
`category_id`, `sort`** — but `search_provider` never passes them, and the handler
(`handleSearch` reads only `q`, `page`, `per_page`, `market`) and `SearchSummary` ignore
them. So even the client-ready params hit a void at the handler.

**Net:** every user-toggleable filter (price / brand / rating / free-shipping) and sort
is dropped at the backend handler. `category_id` is honored on `/products` only — but
that is the listing's *identity* (set by navigation, `filter_panel.dart:146` does
`context.push('/categories/{id}')`), not a panel filter. The browse loop works; refinement
does not.

---

## §4 — Decision matrix

| Filter | UI exists? | Writes state? | Client param ready? | Backend applies? | Decision |
|---|:--:|:--:|:--:|:--:|---|
| Sort | yes | yes | `/products`+`/search` | **no** (handler drops) | blocked → P-028 |
| Price range | yes | yes | `/search` only | **no** | blocked → P-028 |
| Brand | yes (desktop) | yes | no | **no** | blocked → P-028 |
| Rating | yes (desktop) | yes | no | **no** | blocked → P-028 |
| Free shipping | yes | yes | no | **no** | blocked → P-028 |
| In-stock / cashback | yes (mobile sheet) | **no** (dropped on bridge) | no | **no** | §8 frontend cleanup |
| Category | yes (tree) | n/a (navigates) | yes | yes (`/products`) | already works |

All wire-candidate dimensions are **blocked**. Zero rows in the "wire" column → **Outcome C**.

There is no honest Outcome-B subset: wiring `search_provider` to pass the already-supported
`min_price`/`max_price`/`sort` would change **no** results (the handler ignores them), so it
would not satisfy "result list rebuilds on filter change" — it would be cosmetic plumbing
that still looks inert to the user. Per prompt §1.3/§3, commits 2–8 are skipped.

---

## §5 — Existing Riverpod state shape (already built — no change needed)

```dart
// plp_filters.dart — the substrate a future wiring PR connects to the fetch.
class PlpFilters {
  final PlpSort sort;            // recommended | bestseller | newest |
                                 // priceAsc | priceDesc | cashbackDesc
  final int? priceMinMinor;
  final int? priceMaxMinor;
  final List<String> brands;
  final int? ratingMin;          // 1..5
  final bool freeShippingOnly;
  final int page;
  // copyWith (sentinel-based), isEmpty, activeChipCount, ==/hashCode all present.
}
// plpFiltersProvider: NotifierProviderFamily<…, PlpFilters, String>
//   key = '<categoryId>'  or  '_search:<query>'
```

The state, codec, URL hydration (`category_products_screen.dart:51-66`), and debounced
URL write-back (`:74-85`) are complete and correct. A future frontend-wiring PR (once
P-028 lands) only needs to (a) make `filteredProductsProvider` / `searchProvider` watch
the full filter state instead of just `.sort`, and (b) pass the fields to the (then
filter-aware) API methods.

---

## §6 — Golden prediction

**None.** Outcome C ships discovery + docs only — no widget code changes — so no golden
flips. (For reference, the surfaces a future wiring PR would touch:
`catalog/search_goldens_test.dart`, `catalog/plp/goldens`.)

---

## §7 — New finding filed: P-028 (HIGH, backend)

**P-028 — Catalog/search API applies no filter or sort dimension (blocks P-026).**
The `/products` and `/search` handlers, the `catalog.Service` (`ListProductsByCategory`,
`SearchSummary`), and the repository accept no `sort`, `min_price`, `max_price`, `brand`,
`rating_min`, or `free_shipping` argument. Even spec-declared params (`sort` on both;
`min_price`/`max_price`/`category_id` on `/search`) are dropped at the handler. Full-stack
work required: OpenAPI spec (add `brand`/`rating_min`/`free_shipping`/`sort` to `/products`;
they already exist partially on `/search`) → regen → handler parse → service/repo SQL
(`ORDER BY` for sort; `WHERE` for price/brand/rating; a `free_shipping` data field that
`ProductSummary` does not yet carry). Severity bumped MED→HIGH vs P-026 because it is a
multi-dimension, both-endpoint, full-stack feature blocking the core browse loop's
refinement, not a one-line wiring.

---

## §8 — Secondary observations (NOT P-026 — logged for backlog)

1. **Sort-token contract mismatch.** `PlpSort` tokens (`plp_filters.dart:7-13`) are
   `recommended, bestseller, newest, price_asc, price_desc, cashback_desc`. The OpenAPI
   `/products` + `/search` `sort` enum is `[recommended, newest, price_asc, price_desc,
   best_selling]` — `bestseller`≠`best_selling`, and `cashback_desc` is absent. P-028's
   sort work must reconcile these (and decide whether `cashback_desc` is a supported sort).
2. **Mobile/desktop filter divergence.** Mobile `FilterSheet` (`ProductFilterOptions`:
   price, shipping, in-stock, cashback-only) vs desktop `FilterPanel` (`PlpFilters`:
   brand, price, rating, shipping). `in_stock`/`cashback_only` are dropped on the bridge
   (`category_products_screen.dart:272-279`); brand/rating are absent on mobile. Unifying
   them is a frontend-consistency task (a redesign, explicitly out of P-026 scope).
3. **Code-comment inaccuracy.** `filtered_products_provider.dart:11-13` says *"the catalog
   API only filters by sort today."* Discovery shows the backend does **not** apply sort
   either — sort is also a no-op server-side. The comment should be corrected when P-028
   lands (left untouched here — no code changes in an Outcome-C PR).

---

## §9 — What a future frontend-wiring PR will do (queued behind P-028)

1. `filteredProductsProvider`: watch the whole `PlpFilters` (not just `.sort`); pass
   price/brand/rating/shipping/sort to the filter-aware `listProducts`.
2. `searchProvider`: pass `min_price`/`max_price`/`sort`/`category_id` (+ brand/rating
   once spec'd) from `plpFiltersProvider('_search:<q>')` to `api.search(...)`.
3. Empty-results state for over-filtered queries (`CatalogShell` already has an empty path
   — verify it is reached).
4. Tests: filter→query param assertion (mocked API) + chip-remove + clear-all.
5. Goldens: re-baseline active-filter + empty-results surfaces.

This is bounded (~frontend-only) once P-028 makes the API filter-aware.

---

## §10 — Outcome A wiring (frontend-wiring PR, `feat/wire-frontend-filters`)

P-028 (PR #85) shipped the filter-aware backend + regenerated client; this PR wires the
existing UI to it. Re-verified the current state (post-#85 main):

**Already built/wired (no change needed):**
- `PlpFilterChips` — each chip's `onDeleted` already writes through `plpFiltersProvider`, and
  clear-all (`set(const PlpFilters())`) fires at `activeChipCount >= 2`. They were "inert" only
  because the **fetch providers didn't react** — wiring those (below) makes the chips live.
  → **commit "indicators" is a no-op.**
- `FilterPanel` (desktop) writes brand/price/rating/free-shipping to `plpFiltersProvider`.
- `CatalogShell` already renders an empty path → **commit "empty-state" is a no-op** (verify reached).

**The two fetch wires (the core of this PR):**
1. `filteredProductsProvider` (PLP): currently `ref.watch(...select((f)=>f.sort))` + passes only
   `categoryId/page/sort`. → watch the **whole** `PlpFilters`; pass min/max price, brands, rating,
   free_shipping, in_stock, sort to `api.listProducts`. (Filter mutations already set `page:1`;
   `loadMore` doesn't touch `PlpFilters.page`, so whole-object watch is safe.)
2. `searchProvider` (singleton, decoupled, query-keyed filter): `_load` **reads**
   `plpFiltersProvider(plpKeyForSearch(query))` at fetch time + passes the dims to `api.search`;
   `search_screen` adds `ref.listen` on that provider → `searchProvider.notifier.reapplyFilters()`
   to refetch on filter change. (Reading-at-load means a new query naturally gets fresh filters —
   the key changes with the query.)

**in_stock:** the mobile `FilterSheet` has an `inStock` toggle but `PlpFilters` lacked the field, so
the bridge (`_showFilterSheet`) dropped it. → add `inStock` to `PlpFilters` (+ copyWith/isEmpty/
activeChipCount/==/hashCode), the codec (`stock=in`), the bridge mapping, an in-stock chip
(reusing `catalog.filter_in_stock`), and both providers. (Desktop `FilterPanel` gains no in-stock
control — no redesign per scope; in_stock is mobile-settable.)

**UI decisions (§2.3), with discovery overriding the prompt's defaults where evidence warrants:**
- **bestseller → HIDE** (not the prompt's default "rename to Recommended"). `PlpSort` has BOTH
  `recommended` AND `bestseller`; renaming bestseller's label to "Recommended" would show **two
  identical "Recommended" options** (both order identically until P-029). Hiding it from the sort
  selectors (filter `_sortOptions` + `_sortDropdown` at render; keep the enum value + i18n key for
  P-029) leaves exactly the 5 backend-supported tokens. A deep-linked `sort=bestseller` URL still
  resolves (→ backend maps to recommended). Honest + no duplicate; reverts cleanly when P-029 lands.
- **cashback_only → DISABLE + tooltip** (prompt default B). The mobile `FilterSheet` toggle is
  disabled with an informational hint ("Tüm Mopro ürünleri cashback kazanır") — communicates the
  brand fact rather than silently dropping the control.

**category_id-as-filter:** no UI control exists (PLP category is navigation; search `FilterPanel`
hides the category tree). Not wired — documented, not a gap.

**Golden prediction:** the filter UIs are mostly modals/popups (sort sheet, filter sheet) + the
result grids are unchanged (fakes return the same data), so flips should be minimal. Candidates:
`filter_sheet` golden (cashback row disabled style) if one exists; sort goldens if they capture the
sheet. Predict + regen via the ubuntu `golden-rebaseline` workflow (never darwin).
