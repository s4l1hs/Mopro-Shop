# Home PROBABLE resolution — source-side pass (not a visual walk)

The legitimate substitute for a manual Trendyol walk: settle each Home **PROBABLE**
row with what **source** (definitive, Mopro side) + **well-documented convention**
(provisional, Trendyol side, ~May 2025, *not visually verified*) can legitimately
decide. Fix the source-confirmed gaps; hand the genuinely-visual / feature / IA
residue to Salih. **No fabricated "I observed Trendyol" claims.**

This is the **template** for the other surfaces (PDP, Cart, Checkout, Account,
Orders, Returns, Search, Favorites, PLP).

## Method (per row)
1. **Mopro side (fact):** read the impl, state what renders, with file refs.
2. **Trendyol side (provisional):** the documented convention, tagged
   *"convention, ~May 2025 — not visually verified."*
3. **Verdict:** CONFIRMED-fixable · NOT-ACTIONABLE (already-matches / intentional) ·
   NEEDS-VISUAL (pixel/spacing/color/animation neither source nor convention can
   settle — flag, don't guess) · NEEDS-DECISION (a feature build vs. intentional
   omission — Salih's product/IA call, not a pixel question).

## Per-row resolution

### HP-01 — "Sepette %X İndirim" basket-discount pill → NOT-ACTIONABLE (already implemented; audit stale)
- **Mopro (fact):** `product_card.dart` renders `_BasketDiscountPill` ("Sepette %X
  İndirim", brand-orange, under the price) when `basketDiscountPct != null`
  (`product_card.dart:229-232, 399-429`). `ProductSummary.basketDiscountPct` exists
  (`product_summary.dart:302`) and **every** card call site wires it
  (`product_rail.dart:98/202`, `product_list_rail.dart:69`, `product_grid.dart:33`).
  i18n `product.basket_discount = "Sepette %{pct} İndirim"`. Exercised by
  `product_card_test.dart`.
- **Trendyol (provisional):** shows a "Sepette %X" basket-price pill on many cards
  (convention, ~May 2025 — not visually verified).
- **Verdict:** the card-anatomy gap the audit recorded is **closed** — implemented
  end-to-end (G-3 / CT-09 catalog vertical) **after** the audit was seeded. Runtime
  visibility depends on the backend emitting `basket_discount_pct` (CT-09; live for
  the seeded discounted products), which is a backend concern, not a Home card gap.

### HP-02 — per-card "Çok Satan" bestseller badge → NOT-ACTIONABLE (already implemented; audit stale)
- **Mopro (fact):** `product_card.dart` stamps `_BestsellerBadge` ("Çok Satan",
  flame icon, brand-orange ribbon, top-left) when `isBestseller == true`
  (`product_card.dart:153, 329-362`). `ProductSummary.isBestseller` exists
  (`product_summary.dart:276`); all call sites wire `p.isBestseller ?? false`.
  i18n `product.bestseller = "Çok Satan"`.
- **Trendyol (provisional):** stamps a "Çok satan" ribbon on bestselling cards
  (convention, ~May 2025 — not visually verified).
- **Verdict:** closed — implemented end-to-end (G-3). The bestseller *signal* flows
  from the popularity pipeline (P-029 global / P-031 per-category); the card badge
  the audit flagged exists.

### HP-03 — category pucks circular → NOT-ACTIONABLE (already implemented; audit stale)
- **Mopro (fact):** `home_category_rail.dart:133` — `_CategoryPuck` is now
  `shape: BoxShape.circle` ("Trendyol-style circular category puck (G-4)", 52×52).
  The audit recorded rounded-square radius-14; that was changed by G-4.
- **Trendyol (provisional):** category shortcut pucks are circular (long-standing,
  well-documented convention — ~May 2025, not visually verified).
- **Verdict:** closed — the shape now matches the convention.

### HP-04 — no camera / visual-search icon in the search pill → NEEDS-DECISION (feature; not a pixel)
- **Mopro (fact):** `_HomeTopBar` search pill has a search icon
  (`home_screen.dart:297`) + a mic icon (`:328`); **no camera icon**. Confirmed
  absent in source.
- **Trendyol (provisional):** the search bar carries a camera (visual-search) icon
  (convention, ~May 2025 — not visually verified).
- **Verdict:** the *icon* is source-confirmed missing, but its only honest
  resolution is the **visual-search feature** (route + image pipeline). A camera
  icon wired to nothing is a fake affordance (anti-goal). → **DEFER (feature)**;
  Salih decides build-vs-omit. **Not** a NEEDS-VISUAL/pixel item.

### HP-05 — no location/address selector in the header → NEEDS-DECISION (feature + IA; not a pixel)
- **Mopro (fact):** `_HomeTopBar` = search pill + `NotificationBell` + coin pill
  only; **no location/address selector**. Cart/fav live in the bottom nav.
- **Trendyol (provisional):** header has a "deliver to <address>" location selector
  (convention, ~May 2025 — not visually verified).
- **Verdict:** source-confirmed missing, but resolving it = an **address-on-Home**
  feature, and the audit's own walk-note flags it may be an **intentional
  mobile-first IA omission** (header chrome lives in the bottom-nav IA). → **DEFER
  (feature + IA decision for Salih)**. Not a pixel item.

## Outcome

| Row | Verdict |
|---|---|
| HP-01 basket-discount pill | NOT-ACTIONABLE — already implemented (audit stale) |
| HP-02 bestseller badge | NOT-ACTIONABLE — already implemented (audit stale) |
| HP-03 circular pucks | NOT-ACTIONABLE — already implemented (audit stale) |
| HP-04 camera icon | NEEDS-DECISION (Salih) — visual-search feature vs. omit |
| HP-05 location selector | NEEDS-DECISION (Salih) — address-on-Home feature vs. intentional mobile-first IA |

**Zero code fixes:** the three card/puck rows were already closed by the post-audit
catalog vertical (G-3 / G-4); the two header rows are feature/IA calls, not gaps a
source pass can or should "fix" (and not fakeable). **NEEDS-VISUAL (pixel) residue
for Home: none** — every PROBABLE row was presence/shape, which source settled.

**Discovery shift:** the audit's §5 PROBABLE table was *stale* — HP-01/02/03 were
seeded before the catalog vertical landed the pill, the badge, and the circular
puck. The honest result is that Home needs no visual walk for these rows; the only
open items are two product/IA decisions for Salih.

## Salih's list (decisions, not pixel-peeping)
1. **HP-04** — add a visual-search (camera) feature, or confirm intentional omission?
2. **HP-05** — add an address/location selector to Home, or confirm the mobile-first
   bottom-nav IA deliberately omits header chrome?
