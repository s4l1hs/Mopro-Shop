# Sprint B — Desktop Product Rails: Hover-Chevron Carousel — discovery

> Replace the static desktop grid (`RailLayout.grid`) with an infinite horizontal
> scroller + left/right hover chevrons (Trendyol web rail behavior). Mobile
> (<600dp) keeps its existing touch scroll, untouched. Paths verified on
> `feat/desktop-rail-carousel`.

## `RailLayout` + where `.grid` is chosen

- **Widget:** `ProductRail` (`lib/features/catalog/widgets/product_rail.dart`).
  `enum RailLayout { scroller, grid }`. The build switches on `layout`:
  - `scroller` → inline horizontal `ListView.separated` (height 258, card 152w)
    — **the mobile path; preserve verbatim** (`product_rail.dart:84–104`).
  - `grid` → `_RailGrid` = `GridView.builder` (`crossAxisCount`,
    `childAspectRatio 0.62`, capped to `maxItems`).
- **Breakpoint selection** (`home_screen.dart:41–58`):
  `railLayout = context.isMobile ? scroller : grid`;
  `gridColumns = isDesktop ? 5 : 3`; `maxItems = isDesktop ? 10 : 6`.
  So `.grid` serves **both tablet (3-col/6) and desktop (5-col/10)**.
- **Second `.grid` user:** `_EditorsPicksSection` (`home_screen.dart:198`,
  desktop-only) — `ProductRail(layout: grid, maxItems: 6)`. It converts too.
- **NOT affected (separate widgets, already scrollers):** `ProductListRail`
  (recs + recently-viewed rails — `_RecommendationsSliver`/`_RecentlyViewedSliver`),
  `FlashDealsRail`, `HomeCategoryRail`. None use `RailLayout.grid`.

## Hover pattern to mirror

- **`HoverRegion`** (`lib/design/responsive/hover_region.dart`) — `MouseRegion`
  wrapper exposing a `hovering` flag to a builder, with debounced open/close +
  **keyboard-focus treated as hovering** (the mega-menu pattern). Reuse this to
  drive the chevron `AnimatedOpacity` fade — gives a11y (focus reveals chevrons)
  for free.

## ScrollController / animate pattern

- Banner carousel uses `PageController.animateToPage` (`home_screen.dart:386`);
  for a free-scroll rail we use a `ScrollController` + `animateTo(offset, …)`.
- Chevron tap target = `(offset ± viewportDimension).clamp(0, maxScrollExtent)`,
  `animateTo` 300ms `easeInOut`. Extent gating reads `position.pixels` vs
  `maxScrollExtent` via a controller listener (default at-start before attach).

## Decisions (escape hatch §1.3)

- **Breakpoint scope (B):** tablet (touch) → carousel **without** chevrons;
  desktop (pointer) → carousel **with** hover chevrons. Gated by
  `context.isDesktop` inside the carousel — hover-chevrons only where a pointer
  exists. (`MouseRegion` never fires on touch anyway, but we skip building the
  overlay on tablet for cleanliness.)
- **`maxItems`:** keep as a **sane upper bound** (desktop 10, Editor's Picks 6),
  not a hard visual cap — the full set up to the bound is now reachable by
  scrolling instead of clipped into a grid.
- **Outcome A (clean swap), no split.** Scope is contained (one widget, 2 call
  sites); shipping scroller + chevrons + gating together.

## Implementation shape

- Rename `RailLayout.grid` → `RailLayout.carousel`; delete `_RailGrid`,
  `_SkeletonGrid`, and the now-dead `gridColumns` param + its `home_screen`
  computation.
- New `_RailCarousel` (StatefulWidget): horizontal `ListView.builder` (lazy),
  `ScrollController`, items sliced to `maxItems`, card **200×340** (mobile
  152×258 ratio scaled up). Wrapped in `HoverRegion`; left/right **white circular
  floating chevron cards** in a `Stack`, faded via `AnimatedOpacity` when
  `hovering && context.isDesktop`, `IgnorePointer` when hidden. Tap → animate one
  viewport; listener gates left@offset-0 / right@maxExtent.
- `home_screen`: `railLayout = isMobile ? scroller : carousel`; Editor's Picks →
  carousel. Mobile `scroller` branch untouched.

## Affected goldens (predict)

- **`home_tablet_768`** — rails grid → carousel (no chevrons). FLIP.
- **`home_desktop_1440`** — rails + Editor's Picks grid → carousel; chevrons
  present but **opacity 0 at rest** (no hover in golden) → invisible. FLIP.
- **`home_mobile_375`** — mobile scroller path untouched → **NO flip**.
- `recs_*`, `flash_deals_*`, `product_list_rail_*`, `home_category_rail` render
  separate scroller widgets → **NO flip**. No dedicated `product_rail` golden.

## Tests to update / add

- `product_rail_test.dart` — the `grid → GridView` assertion is rewritten for the
  carousel (horizontal ListView; chevrons on desktop hover; gated; lazy build).
- `home_rails_layout_test.dart` — overrides `productsRailProvider` with **empty**
  data (title-count only) → **unaffected**.
- New coverage: chevron appears on hover + hides at rest, scroll advances on tap,
  gated at both extents, tablet has no chevrons, mobile path unchanged.
