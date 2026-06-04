# P-004 + P-009 Frontend Wiring — Discovery

Render the ProductSummary fields PR #88 enriched: favorites count (P-004) + free-shipping
badge (P-009) on the product card. Branch `feat/wire-card-badges`.

## §1 — What's available + where

- `ProductCard` (`mobile/lib/features/catalog/widgets/product_card.dart`) takes a generated
  `ProductSummary product` and reads `product.*` directly. PR #88's `ProductSummary` (Dart) now has
  `favoritesCount` + `freeShipping` (+ `discountPct` already rendered via the legacy `discountPct` param).
- **Two ProductSummary paths feed cards:**
  1. Generated client (`listProducts`/`search`) → `ProductSummary.fromJson` parses `favorites_count` +
     `free_shipping` → **populated**.
  2. Custom mapper `productSummaryFromApi` (`catalog/data/product_summary_api.dart` — used by
     recommendations / recently-viewed / similar) → **does NOT map the new fields** (predates #88) → they
     default to 0/false. **Must add 2 mapper lines** so path-2 cards populate them (the hand-written
     endpoints' JSON already carries them via `buildProductSummaryJSON`, #88).
- `free_shipping` label already in i18n: `plp.free_shipping` = "Ücretsiz Kargo" / "Free Shipping" → **reuse**
  (verbatim-reuse discipline; no new key).
- The `DiscountPill` (`design/widgets/discount_pill.dart`, PR #78) already renders the discount badge on the
  card — **P-009's discount portion is already done**; only the free-shipping badge is new.

## §2 — Scope decision: card only (PDP is out of scope)

P-004 ("**product card** lacks favorites-count") and P-009 ("**search-result cards** lack badges") are
**card findings**. The PDP (`product_detail_screen.dart`) uses the full `Product` (GetProduct), which PR #88
did **not** enrich — so a PDP count/badge is backend-gated (Product-detail enrichment, a separate follow-up)
**and outside the original findings' scope**. This PR resolves P-004 + P-009 on every card surface (list,
search, home rails, flash deals, favorites grid, recommendations) and notes the PDP as a non-finding follow-up.

## §3 — UI decisions (§2.3 defaults; anti-bikeshed)

- **Favorites count (P-004):** a small non-interactive overlay pill on the image (bottom-left) — `♥ {count}`,
  distinct from the top-right toggle (which is the user's action; the count is global social proof). **No
  optimistic update** (anti-goal) — shows the server count, refreshes on reload. Formatter
  `formatCompactCount(int)`: `< 10` → hidden (avoid "♥ 3" noise); `10–999` → raw; `≥ 1000` → `"1.2K"` (period
  + K — universally read, avoids Turkish compact "B"/bin confusion). Testable plain function in `lib/utils/`.
- **Free-shipping badge (P-009):** a small pill (shipping icon + "Ücretsiz Kargo" via `plp.free_shipping`) in
  the text block, rendered only when `product.freeShipping`. **Color:** `onSurfaceVariant` text (an
  already-AA-tested pair, P-020) — **no new token** (a green treatment is a future polish needing a token).
- **Flash badge:** **deferred** — no clear catalog-derivation rule (it's campaign/popularity-shaped, P-029
  territory). `flash_price_minor` already drives the flash *price* on `FlashDealsRail`; a flash *badge* is out.

## §4 — Golden prediction

**Zero flips expected.** Card golden fixtures (and the search/PLP fake-API cards) use the `ProductSummary`
defaults (`favoritesCount = 0`, `freeShipping = false`), so the count is hidden (<10) and the badge absent —
identical to today. New rendering only appears with non-default data, which the new widget tests supply (not
goldens). Verify via CI `flutter test`; rebaseline only if an unexpected flip surfaces.

## §5 — Commit plan
1. discovery (this doc)
2. P-004: `formatCompactCount` util + card favorites-count overlay + mapper `favorites_count` line + tests
3. P-009: card free-shipping badge + mapper `free_shipping` line + tests
4. docs closure (audit P-004/P-009 RESOLVED; ROADMAP; REPORT)

(No separate goldens commit unless CI surfaces a flip; tests fold into 2/3 — smallest PR in the arc.)
