# Trendyol Parity Audit — PLP / Category-Browse

> **Audit only — no code changed.** Self-audit of the current PLP
> (product-grid-with-filters reached from the category pucks and from search)
> against a **provisional** ~May-2025 Trendyol baseline. The baseline is a
> checklist, **not truth** — every row is "confirm against live" in Salih's walk.
> Sibling of `TRENDYOL_PARITY_HOME_AUDIT.md`; findings use the #09 format.
>
> **Surface under audit:** `CategoryProductsScreen`
> (`lib/features/catalog/screens/category_products_screen.dart`) + its substrate:
> `CatalogShell`, `FilterPanel` (desktop sidebar), `FilterSheet` (mobile sheet),
> `PlpFilterChips`, `sort_sheet.dart`, `PlpFilters`/`filtered_products_provider`.
> The same shell + `FilterPanel` back **SearchScreen** (filters cascade to the
> later search audit — `FilterPanel.showCategoryTree=false` there).

---

## §1 — Summary (provisional, pre-walk)

- **PROBABLE deltas: 11** (PLP-01…PLP-11) — mostly **mobile/desktop filter
  parity** (mobile sheet is a subset) + **load-more vs infinite-scroll** +
  missing chrome (result count, breadcrumb, quick pills). None are structural;
  the desktop PLP is already Trendyol-shaped.
- **NOT-ACTIONABLE (intentional / Mopro PLUS): 4** (D1–D4).
- **Already-matched (VERIFIED from source): ~10** — desktop sidebar
  (searchable brands, price slider+fields, rating buckets, free-shipping, clear-
  all), 6-option sort (dropdown + sheet), responsive grid reusing the parity'd
  card, removable applied-chips (desktop), load-more w/ spinner+retry, empty +
  error states, live (no-apply) filtering, URL-synced shareable filters.
- **Highest-value-if-confirmed:** PLP-01 (mobile can't filter by brand/rating)
  and PLP-03 (manual load-more vs infinite scroll). Both interaction parity.
- **Seed caveat (see §5):** global facet variety is rich, but **per-category
  density is 2–3 products** — a single category PLP can't meaningfully exercise
  the filters during the walk without an aggregating parent or a seed bump.

---

## §2 — Self-audit table (Mopro-current vs provisional baseline)

| Baseline item | Mopro current (from source) | Delta | Status |
|---|---|---|---|
| **Filters — desktop sidebar** (category, brand searchable, price, rating, attrs, free-cargo/fast-delivery; apply + clear-all; live count) | `FilterPanel`: category tree, **searchable brand list** (search box + show-more >8), price **RangeSlider + min/max fields**, rating (All/4+/3+/2+), free-shipping switch, clear-all + (no-op) apply. Live-applied via URL. | **No fast-delivery** toggle (only free-cargo); **no in-stock** in the desktop panel (it's in the model + mobile only → PLP-11); **no brand counts** (PLP-07); no attribute/variant facets | **PROBABLE** (mostly matched) |
| **Filters — mobile bottom-sheet** (same set as desktop) | `FilterSheet`: price min/max, free-shipping, in-stock, cashback-only (**disabled**). **No brand, no rating, no category.** | Mobile is a **strict subset** of desktop — can't filter by **brand or rating** on a phone | **PROBABLE** — **PLP-01** (MED candidate) |
| **Applied-filter chips** (removable, above grid) | `PlpFilterChips`: one removable `InputChip` per active filter + clear-all (≥2). **Desktop `_buildWide` only.** | Mobile shows a filter-count **badge** on the bar, **no removable chips** | **PROBABLE** — **PLP-02** |
| **Quick-filter pills** above the grid | None (applied-chips ≠ predefined quick pills) | No one-tap common-filter pills | **PROBABLE** — **PLP-06** (LOW) |
| **Sort** — dropdown: recommended, price ↑/↓, newest, bestseller, rating | `PlpSort`: recommended, bestseller, newest, price_asc, price_desc, **cashback_desc**. Desktop `PopupMenuButton` + mobile `sort_sheet`. | **No "rating" sort**; **cashback_desc** added (brand → D1) | **PROBABLE** (near-match) |
| **Grid** — 2-col mobile / multi-col desktop, parity'd card | `ProductGrid` via `CatalogShell`: **2 mobile / 3 tablet / 5 desktop**, reuses `ProductCard` (badges / "Sepette %X" pill / rating / bestseller) | Matches | **NOT-ACTIONABLE** (matched) |
| **Result count** + breadcrumbs | `pagination.total` **is returned** but **not surfaced**; no count text. Breadcrumb is **JSON-LD only** (SEO) — no visible UI; AppBar shows the category title | No visible count (**PLP-04**); no visible breadcrumb (**PLP-05**) | **PROBABLE** (LOW each) |
| **Pagination** — infinite scroll (mobile) / load-more (desktop) | **Manual "Load more" button** on **both** (spinner while loading, error-retry banner). No scroll-triggered auto-load. | No mobile **infinite scroll** | **PROBABLE** — **PLP-03** (MED candidate) |
| **Empty / no-results** with suggestions or reset | `EmptyState.empty()` — message only; `onAction` **not wired** | No **clear-filters** CTA in the zero-results state | **PROBABLE** — **PLP-08** (LOW) |
| **Header** — search bar + category title | AppBar: category **title** + **share** button. No search bar on the PLP. | No in-PLP search affordance | **PROBABLE** — **PLP-10** (LOW) |

---

## §3 — Intentional divergences (NOT-ACTIONABLE — do not flag as gaps)

- **D1 — Cashback sort + cashback-only filter.** `cashback_desc` sort and the
  (disabled) cashback-only toggle are Mopro's perpetual-cashback model, not a
  Trendyol miss. The cashback filter is intentionally vacuous (every product
  earns cashback — P-028) with an explanatory hint.
- **D2 — URL-synced, shareable/deep-linkable filters + SEO.** `PlpFiltersCodec`
  round-trips all filters to/from the query string; `SeoHead` + JSON-LD
  breadcrumb/structured-data. A Mopro **PLUS** beyond the baseline.
- **D3 — Brand-orange active tokens** (`colorScheme.primary`) on selected
  filters/sort — the Mopro brand token, not a parity defect.
- **D4 — Share button on the PLP** (`MoproShareButton`) — additive.

---

## §4 — Already-matched (VERIFIED from source — re-open only if the walk disagrees)

Desktop sidebar (category tree, **searchable** brand list, price slider+fields,
rating buckets, free-shipping, clear-all) · 6-option **sort** (desktop dropdown +
mobile sheet) · responsive **grid** (2/3/5) reusing the parity'd `ProductCard` ·
**removable applied-chips** + clear-all (desktop) · **load-more** with
spinner + error-retry · **empty + error** states · **live filtering** (no manual
apply needed) · **URL-synced** filter state.

---

## §5 — Seed-facet adequacy (for the walk)

- **Global variety is rich:** `scripts/seed/data/products.json` = **50 products,
  25 distinct brands** (Nike, Adidas, Apple, Samsung, Sony, Koton, LC Waikiki,
  Dyson, IKEA, …), **11 distinct rating values**, price spread **₺89 → ₺89,999**.
- **But the PLP is category-scoped and per-category density is 2–3 products**
  (max 3: `spor-fitness`, `moda-ayakkabi`, `kozmetik-cilt`, `elektr-kea`). Within
  one leaf category the searchable brand list (designed for >8 brands), the price
  RangeSlider, and the rating buckets have **almost nothing to act on**.
- **RESOLVED (PLP-SEED, `chore/plp-seed-density`):** the PLP scopes by **exact
  `category_id` — no subtree rollup** (`repository.go:373`), so option (a) is out
  (and is itself a finding → **PLP-12**). Shipped option (b) as a dev-only
  idempotent `scripts/seed/data/plp-density-extras.sql` that concentrates **~28
  existing SKUs into `elektr-kea` ("Küçük Ev Aletleri")** + spreads ratings + sets
  free-shipping. **Walk category: `elektr-kea`** — verified **28 products / 23
  brands / rating buckets 2+/3+/4+ distinct / ₺89–₺89,999 / free-ship populated**.
  Apply: `psql … < scripts/seed/data/plp-density-extras.sql` after `make seed`.
  See `docs/internal/plp-seed-density.md`.

- **PLP-12 (new finding — no subtree rollup):** because product scoping is exact
  `category_id`, **parent/root category PLPs are empty** (the 6 roots
  `root-elektronik` … have zero direct products — products live on leaves).
  Trendyol rolls a category's whole subtree into the PLP. **PROBABLE** (MED?) —
  confirm in the walk; **not built here** (would be a backend change).

---

## §6 — Walk-findings slots (Salih — paste live-Trendyol observations here)

> One block per observation. On confirming a §2 row, set its **Status** to
> CONFIRMED + **Severity**; add new items as PLP-12, PLP-13, …. Mark anything the
> walk decides is intentional **NOT-ACTIONABLE** + why. Severity only when CONFIRMED.

```
### PLP-NN — <one-line title>
- **Surface/region:** PLP › <filter sidebar | mobile filter sheet | chips | sort | grid | pagination | empty | header | breadcrumb>
- **Trendyol (live):** <what Trendyol does — screenshot ref / observation>  [walk date: ____]
- **Mopro (current):** <what Mopro does — file:line if known>
- **Delta:** <the difference>
- **Status:** CONFIRMED | PROBABLE | NOT-ACTIONABLE
- **Severity:** HIGH | MED | LOW   (only if CONFIRMED)
- **Notes:** <intentional? backend-gated? golden-flip? depends-on?>
```

<!-- ── §2-seed findings (confirm/correct against live) ───────────────────── -->
<!-- PLP-01 — mobile filter sheet lacks brand + rating (+ category). MED? -->
<!-- PLP-02 — applied-filter chips are desktop-only (mobile = count badge). -->
<!-- PLP-03 — manual "Load more" on mobile, not infinite scroll. MED? -->
<!-- PLP-04 — no visible result count (pagination.total is available, unused). -->
<!-- PLP-05 — no visible breadcrumb on desktop (JSON-LD only). -->
<!-- PLP-06 — no predefined quick-filter pills above the grid. -->
<!-- PLP-07 — brand facet has no counts + derived from loaded page, not a server facet. -->
<!-- PLP-08 — no-results state has no clear-filters CTA (EmptyState onAction unused). -->
<!-- PLP-09 — no fast-delivery toggle (only free-cargo). -->
<!-- PLP-10 — no search bar in the PLP header (title + share only). -->
<!-- PLP-11 — in-stock toggle is on mobile sheet but missing from the desktop sidebar. -->

<!-- ── New findings from the walk (PLP-12+) ──────────────────────────────── -->
<!-- PLP-12 — no subtree rollup: PLP scopes by exact category_id
     (repository.go:373) → parent/root category PLPs are empty. PROBABLE; confirm
     in the walk. Surfaced by PLP-SEED (docs/internal/plp-seed-density.md). -->
<!-- PLP-13 … -->

---

## §7 — Prioritized fix list (after the walk flips PROBABLE → CONFIRMED)

1. **PLP-01** — bring brand + rating (+ category) filters to the mobile sheet
   (close the mobile/desktop parity gap). *Likely the highest-value confirm.*
2. **PLP-03** — mobile infinite-scroll (scroll-triggered `loadMore`) alongside
   the load-more button.
3. **PLP-02** — removable applied-chips on mobile.
4. **PLP-04 / PLP-05** — surface result count + a visible breadcrumb (both data
   already exist: `pagination.total`, the JSON-LD trail).
5. **PLP-07 / PLP-08 / PLP-06 / PLP-09 / PLP-10 / PLP-11** — facet counts,
   no-results clear-filters CTA, quick pills, fast-delivery, header search,
   desktop in-stock. LOW; batch as polish.

> Severities are **provisional** until the walk confirms each row. No fixes in
> this PR (audit-only).
