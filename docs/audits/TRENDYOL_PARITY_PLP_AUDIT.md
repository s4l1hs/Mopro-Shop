# Trendyol Parity Audit — PLP / Category-Browse

> **Canonical PLP registry — audit-doc only, no code.** One stable ID per finding,
> each tagged with **evidence source** + **confidence**. Reconciles the original
> #139 audit, Salih's Part-3 contract, and the markup reads (Claude Code + Cowork
> fetch of the homepage + `/cep-telefonu-x-c103498`). `/sr` search is bot-blocked
> (403) → search-specific behavior needs Salih's eyes, not markup.
>
> **Surface:** `CategoryProductsScreen` + `CatalogShell` · `FilterPanel` (desktop
> sidebar) · `FilterSheet`/`PlpFilterSheet` (mobile) · `PlpFilterChips` ·
> `sort_sheet` · `PlpFilters`/`filtered_products_provider`. The same shell +
> `FilterPanel` back **SearchScreen** (these patterns cascade to the search audit).

---

## §0 — Evidence + confidence legend

- **Source tag** — `src` (Mopro code fact) · `walk` (Salih, mobile/visual) ·
  `markup` (Trendyol desktop SSR, **structural** only — not rendered pixels).
- **Confidence** — **CONFIRMED** (structural fact via markup or walk) ·
  **PROBABLE** (visual/interaction — awaiting Salih's visual walk) ·
  **RESOLVED** (shipped) · **NOT-ACTIONABLE** (intentional divergence).
- **Rule:** markup CONFIRMS *structural* facts (a control/element exists) but
  **never** promotes a *visual/interaction* finding to CONFIRMED (markup ≠ pixels).

---

## §1 — Summary

- **RESOLVED: 8** — PLP-01/03 (mobile facets + infinite scroll, #142), PLP-04/05
  (count + breadcrumb), **PLP-15 (desktop numbered pages), PLP-18 (sticky sidebar —
  already-matched), PLP-19 (ultra-wide breakpoints), PLP-20 (sticky mobile bar)**.
- **DEFER'd (backend track): 1** — PLP-13 (attribute facets, Outcome C; ledger §4b).
- **CONFIRMED open (backend/data): 3** — PLP-12 (subtree rollup, **HIGH**),
  PLP-14 (price-history filter), PLP-09 (fast-delivery).
- **PROBABLE (await visual walk): 5** — PLP-02, PLP-06, PLP-07 (softened), PLP-08,
  PLP-10, + the unnumbered visual bucket (§9).
- **NEW from markup: 5** — PLP-13, PLP-14, PLP-15, PLP-16, PLP-17.
- **NOT-ACTIONABLE (intentional / Mopro PLUS): 4** — D1–D4 (§5).
- **CONFIRMED-HIGH fix queue:** §8.

---

## §2 — Canonical ID map (drift resolution — nothing lost)

This doc's **PLP-01…PLP-12 are canonical** (they're the published registry + the
IDs PR #142 shipped against). New findings take **PLP-13…PLP-20**. Aliases:

| Canonical | Finding | Prior / alias IDs |
|---|---|---|
| **PLP-01** | mobile sheet: brand + rating facets (RESOLVED) | audit PLP-01; **contract "PLP-25"** (bundled with PLP-03) |
| **PLP-03** | mobile pagination: infinite scroll (RESOLVED) | audit PLP-03; **contract "PLP-25"** |
| **PLP-04** | no visible result count | audit PLP-04 |
| **PLP-05** | no visible breadcrumb | audit PLP-05 |
| **PLP-07** | brand-facet counts (softened) | audit PLP-07 |
| **PLP-12** | no subtree rollup | ledger §4 PLP-12 |
| **PLP-18** | sticky desktop sidebar | **contract/ledger "PLP-02"** ⚠ |
| **PLP-19** | ultra-wide grid breakpoints | **contract/ledger "PLP-05"** ⚠ |
| **PLP-20** | sticky mobile sort/filter bar | **contract/ledger "PLP-07"** ⚠ |

> **⚠ The PLP-02/05/07 collision (resolved):** Salih's contract/ledger reused
> `PLP-02/05/07` for *sticky-sidebar / ultra-wide-grid / sticky-mobile-bar*, which
> already mean *chips / breadcrumb / brand-counts* in this audit. To keep **one
> meaning per ID**, the contract's three findings are re-numbered **PLP-18/19/20**
> here; the audit's PLP-02 (chips), PLP-05 (breadcrumb — markup-CONFIRMED), PLP-07
> (counts) keep their numbers. **`CUTOVER_LEDGER.md §7` updated to match.**
> *Discovery shift to confirm with Salih: this picks the audit's numbering as
> canonical for 02/05/07.*

---

## §3 — Findings registry (canonical)

| ID | Finding (Mopro current → Trendyol) | Source | Confidence | Sev |
|---|---|---|---|---|
| **PLP-01** | ~~mobile sheet had no brand/rating~~ → searchable Brand + Rating accordions added | src+walk | **RESOLVED** (#142) | HIGH |
| **PLP-03** | ~~mobile load-more button~~ → infinite scroll (150px, gated) | walk | **RESOLVED** (#142) | HIGH |
| **PLP-04** | ~~`pagination.total` not shown~~ → **RESOLVED**: `PlpResultCount` renders "N ürün" live (mobile + desktop) from the now-surfaced `ProductsState.total`. | markup | **RESOLVED** | MED |
| **PLP-05** | ~~breadcrumb JSON-LD only~~ → **RESOLVED**: `PlpBreadcrumb` renders the category ancestry (client-side from `Category.parentId`), tappable, mobile + desktop. | markup | **RESOLVED** | MED |
| **PLP-06** | no predefined quick-filter pills above the grid | src | **PROBABLE** | LOW |
| **PLP-07** | brand facet has no counts + derived from the loaded page | src; markup **inconclusive** (counts not in SSR) | **PROBABLE** (softened) | LOW |
| **PLP-08** | no-results state (`EmptyState.empty()`) has no clear-filters CTA | src | **PROBABLE** | LOW |
| **PLP-09** | no **fast-delivery** filter toggle (only free-cargo) → Trendyol has "Hızlı Teslimat" | src+markup | **CONFIRMED** (structural) | LOW–MED |
| **PLP-10** | no search bar in the PLP header (title + share only) | src | **PROBABLE** | LOW |
| **PLP-11** | in-stock toggle on mobile sheet but missing from the desktop sidebar (Mopro-internal) | src | **PROBABLE** | LOW |
| **PLP-12** | exact-`category_id` scoping (`repository.go:373`) → parent/root PLPs empty; **Trendyol rolls the subtree up** (multi-brand under one category, subcats as filters) | markup | **CONFIRMED** | **HIGH** (backend — ledger §4) |
| **PLP-13** 🆕 | **no attribute/variant facets** → Trendyol's deep stack. **DEFER'd (Outcome C)**: only `variants.color/size` are structured (unfiltered + sparse); `products.specs` is opaque per-category JSONB; **no normalized attribute/facet model or aggregation** → a backend data-modeling track (ledger §4b), not a UI add. See `docs/internal/plp-batch.md`. | markup | **CONFIRMED → DEFER** | **HIGH** (backend) |
| **PLP-14** 🆕 | **no price-history *filter*** → "Fiyat Geçmişi". **DEFER (feasible, design-ready)** (Track C): data exists (`variant_price_history`, 0083) + the P-028 param pattern proves it — a `price_dropped` WHERE (§5-safe `EXISTS` over the table). Deferred as its own **codegen vertical** (spec param → Go/Dart regen → toggle UI + chip + goldens). Design: `docs/internal/plp-14-price-history.md`. | markup | **CONFIRMED → DEFER** (ready) | MED |
| **PLP-15** 🆕 | ~~desktop load-more~~ → **RESOLVED**: desktop `_NumberedPages` control (`goToPage` replaces the grid); mobile keeps infinite scroll. | markup | **RESOLVED** | MED |
| **PLP-16** 🆕 | **ranked** bestseller / most-visited badge ("En Çok Satan 1. Ürün") — Mopro has an unranked bestseller stamp | markup | markup-observed | MED |
| **PLP-17** 🆕 | **official-seller** badge ("Resmi satıcı rozeti") / seller-type chips — Mopro has none | markup | markup-observed | LOW |
| **PLP-18** | ~~non-sticky desktop sidebar~~ → **RESOLVED (already-matched)**: `_buildWide` puts the sidebar in a height-bounded, non-scrolling column (the grid scrolls inside its own `CustomScrollView`) → it **already pins**. No code. | src | **RESOLVED** | MED |
| **PLP-19** | ~~flat 5-col + 1240 clamp~~ → **RESOLVED**: width-aware columns 2/3/4/5 + ultra-wide content clamp (1600 ≥1440) — less outer-margin whitespace. | walk | **RESOLVED** | MED |
| **PLP-20** | ~~bar scrolls away~~ → **RESOLVED**: mobile sort/filter bar is a pinned `SliverPersistentHeader` (opaque bg). | walk | **RESOLVED** | LOW |

> Visual-only items (mobile filter-sheet styling, hover chevrons, banner-indicator
> style, exact colours/spacing) stay **PROBABLE** in the §9 bucket — markup can't
> confirm pixels.

---

## §4 — Self-audit cross-check (Mopro source vs Trendyol)

| Area | Mopro (source) | Trendyol | Finding |
|---|---|---|---|
| Desktop sidebar | category tree, searchable brands, price slider+fields, rating, free-ship, clear-all | + **deep attribute facets**, price-history, seller-type, campaign | PLP-13/14/09 |
| Mobile filters | Brand+Rating+price+free-ship+in-stock (RESOLVED) | full set | PLP-01 ✅ |
| Chips | removable, **desktop only** | applied chips on both | PLP-02 |
| Sort | 6 opts incl. `cashback_desc`; no rating-sort | recommended/price/newest/bestseller/rating | near-match (D1) |
| Grid | 2/3/5 cols, parity'd card | ~4–5 cols + ranked/seller badges | PLP-16/17/19 |
| Count / breadcrumb | `total` unused; JSON-LD only | visible count + trail | PLP-04/05 |
| Pagination | load-more (both) → mobile infinite (RESOLVED) | mobile infinite / **desktop numbered pages** | PLP-03 ✅ / PLP-15 |
| Empty | message only | suggestions/reset | PLP-08 |
| Header | title + share, no search | search bar present | PLP-10 |
| Category scope | exact `category_id` | subtree rollup | PLP-12 |

---

## §5 — Intentional divergences (NOT-ACTIONABLE — do not flag)

- **D1 — Cashback sort + cashback-only filter** (perpetual-cashback model; the
  cashback toggle was intentionally vacuous — removed in PLP-01, P-028).
- **D2 — URL-synced, shareable/deep-linkable filters + SEO** (`PlpFiltersCodec`,
  `SeoHead`, JSON-LD) — a Mopro **PLUS** beyond the baseline.
- **D3 — Brand-orange active tokens** (`colorScheme.primary`).
- **D4 — Share button on the PLP** (`MoproShareButton`) — additive.

---

## §6 — Already-matched (VERIFIED from source)

Desktop sidebar (category tree, **searchable** brands, price slider+fields, rating
buckets, free-shipping, clear-all) · 6-option **sort** (dropdown + sheet) ·
responsive **grid** (2/3/5) reusing the parity'd `ProductCard` (incl. "Sepette %X"
pill + bestseller stamp) · **removable applied-chips** (desktop) · **load-more**
w/ spinner+retry · **empty + error** states · **live filtering** · **URL-synced**
state · **mobile brand/rating facets + infinite scroll** (PLP-01/03).

---

## §7 — Seed-facet adequacy (RESOLVED — for the walk)

Global variety is rich (50 products / 25 brands / ₺89–₺89,999 / 11 ratings) but
the PLP is category-scoped (2–3 products/leaf). **PLP-SEED** (`chore/plp-seed-
density`, merged #140) concentrated **~28 SKUs into `elektr-kea`** + spread
ratings + set free-shipping → verified **28 products / 23 brands / 2+/3+/4+ buckets
distinct / free-ship populated**. **Walk category: `elektr-kea`.** Apply
`scripts/seed/data/plp-density-extras.sql` after `make seed`. See
`docs/internal/plp-seed-density.md`. (The empty-parent-PLP this exposed = PLP-12.)

---

## §8 — CONFIRMED-HIGH fix queue (the next fix prompts draw from here)

**Shipped:** PLP-01/03 (#142), PLP-04/05 (count + breadcrumb), **PLP-15/18/19/20**
(numbered pages / sticky sidebar / breakpoints / sticky mobile bar). **DEFER'd:**
PLP-13 (backend track). **Remaining = backend + MED/LOW:**

1. **PLP-13 — attribute/variant facets** → **DEFER (Outcome C)**: no normalized
   attribute/facet model → backend data-modeling track, `CUTOVER_LEDGER.md §4b`.
2. **PLP-12 — subtree rollup** (CONFIRMED, **HIGH**, backend; recursive CTE).
   `CUTOVER_LEDGER.md §4`; backend PR.
3. **PLP-14 — price-history filter** (CONFIRMED, MED). Backend param + control.
4. **MED/LOW batch:** PLP-09 (fast-delivery), PLP-16 (ranked badge), PLP-02
   (mobile chips), PLP-06/07/08/10/11/17 — most are LOW polish or await the
   visual walk (§9).

---

## §9 — Walk-findings slots (Salih — visual confirmation still needed)

> markup CONFIRMED the structural items above. These remain **PROBABLE** until a
> visual/mobile walk — paste observations in #09 format; flip PROBABLE → CONFIRMED
> + set severity, or NOT-ACTIONABLE + why. New items continue at **PLP-21+**.

- Mobile filter-sheet styling/accordions vs Trendyol's bottom sheet.
- PLP-02 mobile applied-chips (Trendyol-mobile unverified — `/sr` was 403).
- PLP-18/19/20 sticky sidebar / ultra-wide grid / sticky mobile bar (walk-sourced).
- Exact colours, spacing, hover chevrons, badge styling.

```
### PLP-NN — <one-line title>
- **Surface/region:** PLP › <sidebar | mobile sheet | chips | sort | grid | pagination | empty | header | breadcrumb | badge>
- **Trendyol (live):** <observation / screenshot ref>  [walk date: ____]
- **Mopro (current):** <file:line if known>
- **Delta / Status / Severity / Notes**
```

<!-- PLP-21 … -->
