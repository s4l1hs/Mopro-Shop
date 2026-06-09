# PLP Layout & Pagination Closeout — PLP-15/18/19/20 — discovery

> Remaining CONFIRMED UI-side PLP gaps. One branch `feat/plp-layout-closeout`,
> per-concern commits. Verified on the branch.

## PLP-15 — desktop numbered pages

- `filteredProductsProvider` already has `_load(page, {replace})` —
  `replace:true` shows only that page (clears+sets), `replace:false` appends
  (`loadMore`, used by mobile infinite scroll). `ProductsState` exposes `total`
  + `page`; **needs `totalPages`** (currently computed inline for `hasMore`).
- **Plan:** add `totalPages` to `ProductsState` (from `meta.totalPages`) + a
  public `goToPage(int) => _load(n, replace:true)`. `CatalogShell` gains
  `currentPage`/`totalPages`/`onGoToPage`; when **not** `infiniteScroll` (desktop)
  it renders a numbered-pages control instead of the load-more button. **Mobile's
  `loadMore`/infinite scroll is untouched** (guarded by the existing
  `infiniteScroll` flag).

## PLP-18 — sticky desktop sidebar → **already matched (no code)**

- `_buildWide` is `LayoutBuilder → Center → ConstrainedBox(1240) →
  SizedBox(height: c.maxHeight) → Row[ FilterPanel(sidebar), grid ]`. The Row is
  **bounded to the viewport height**; the grid scrolls inside its own
  `CustomScrollView` (Expanded), and `FilterPanel` scrolls inside its own
  `Expanded ListView`. So the sidebar **already pins** while the grid scrolls — it
  sits in a separate, non-scrolling, height-bounded column. No clip on short
  viewports (the panel's own ListView scrolls; clear/apply stay pinned at bottom).
- **Discovery shift (§1.3):** PLP-18 is satisfied as-is → mark resolved
  (already-matched), no code. Forcing a `Sticky`/`pinned` wrapper would fight the
  existing layout for no gain.

## PLP-19 — ultra-wide grid breakpoints

- Column count is set in the **screen** (`category_products_screen.dart:137`):
  `isMobile ? 2 : (isDesktop ? 5 : 3)` — a flat 5 across all desktop widths. The
  content is clamped at `ConstrainedBox(maxWidth: 1240)` (`:211`), so >1240px
  screens get outer-margin whitespace. (The prompt cited `catalog_shell.dart`;
  the grid count is *consumed* there but *set* in the screen — **discovery shift**.)
- **Plan:** width-aware count — 2 (mobile) / 3 (tablet) / **4** (desktop
  1024–1439) / **5** (≥1440); and raise the clamp on ultra-wide (≥1440 →
  `min(width, 1600)`) so the grid uses more width (less margin).

## PLP-20 — sticky mobile sort/filter bar

- `_FilterSortBar` is the **first sliver** in `CatalogShell` (a
  `SliverToBoxAdapter`) → it scrolls away. It only renders when
  `onSort`/`onFilter != null` (**mobile only**; desktop nulls them).
- **Plan:** make it a `SliverPersistentHeader(pinned: true)` with a small
  delegate → pins on scroll. Mobile-only by construction; desktop has no bar.

## Goldens (predict)

- Desktop `plp_sidebar_{no_filters,with_filters}_{1024,1440}_{light,dark}` (8):
  **PLP-19** flips the **1024** ones (5→4 cols) and the ultra-wide clamp is ≥1440
  (1440 stays 5 cols / 1240 clamp at exactly 1440 → 1440 may be unaffected or
  shift if clamp raises at ≥1440 — reconcile). **PLP-15:** the fixture is 1 page
  (`totalPages:1`) → no page control rendered → likely no PLP-15 flip in goldens.
- No mobile PLP golden exists → **PLP-20** (sticky bar) has no golden; widget-test
  it. Regen on Linux, reconcile.

## Plan (commits)

1. **PLP-15** — `totalPages` + `goToPage`; `CatalogShell` numbered-pages control
   (desktop); screen wiring + test.
2. **PLP-18** — doc note (already-matched); audit update only.
3. **PLP-19** — width-aware column count + ultra-wide clamp.
4. **PLP-20** — `SliverPersistentHeader` pinned sort/filter bar; test.
