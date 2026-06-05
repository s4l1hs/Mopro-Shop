# P-030 frontend display — discovery

> Consumes PR #92's `ProductSummary.lowest_30d_price_minor` to render the TR/EU
> compliance line ("Son 30 günün en düşük fiyatı: X"). **Stacked on
> `feat/price-history`** (#92) — hard dependency: the generated mobile field only
> exists there until #92 merges. GitHub retargets to `main` on #92 merge.

## 1. The field flows to ProductSummary

- Generated `mopro_api.ProductSummary` already exposes `lowest30dPriceMinor` (#92 regen).
- **list/search cards** get it automatically via the generated `ProductSummary.fromJson`
  (`api.listProducts`/`api.search`).
- **rail cards** (recently-viewed / recommendations / similar) go through the hand-written-shape
  mapper `productSummaryFromApi` (`data/product_summary_api.dart`) — which must add the field
  (same one-line pattern as `favorites_count`/`free_shipping`/`discount_pct` from #88).

## 2. Discovery reshaped the scope (vs the prompt)

| Prompt assumed | Actual |
|---|---|
| add a new i18n key `product.price.lowest_30d` | **key already exists**: `product.lowest_30d` (TR `"Son 30 günün en düşük fiyatı: {price}"`, EN `"Lowest price in 30 days: {price}"`) — reuse, do **not** add |
| build a `Lowest30dPriceLine` widget + integrate on card **and** PDP | **PDP already renders it** — `PdpPriceBlock` has a `lowestIn30DaysMinor` param + the `product.lowest_30d` line (pre-built "dark slot", noted in #88's audit). Card has **no** such line yet → card is the only place to add code |
| PDP is in scope | **PDP is backend-blocked** — the PDP screen uses the full `Product` (from `GetByID`), which does **not** carry `lowest_30d` (it's only on `ProductSummary`); the PDP call passes `PdpPriceBlock(priceMinor: …)` with `lowestIn30DaysMinor` defaulting null. Wiring it needs a backend change to `GetByID`/`Product` → out of scope (anti-goal: no backend) → **defer** |

Net: this PR is **card-only** wiring + the rail mapper. PDP's slot is ready but stays dark until the
backend exposes `lowest_30d` on the product-detail path (a follow-up, see §5).

## 3. Card display logic

Render in `product_card.dart`, below the current price, above the cashback chip, tied to the card's
existing `hasDiscount` (so the line only appears when the discount badge does — visually coherent):

```dart
final low = product.lowest30dPriceMinor;
final showLowest30d = priceOverride == null      // not a flash card (flash price ≠ regular history)
    && hasDiscount                                // a reduction is announced (strikethrough/% pill)
    && low != null
    && low < effectivePrice;                      // current price is NOT the 30-day low
```
Style: `labelSmall` + `onSurfaceVariant` (a documented AA-safe pair on `surface`, both themes — no new
token), `maxLines: 1` + ellipsis (cards are tight — the #89 overflow lesson).

Why `low < effectivePrice`: `lowest_30d <= current` always (current is in the window), so `<` means the
price was lower earlier in the window — i.e. the current "discounted" price is not really the 30-day
low. That is exactly the consumer-protection signal. Suppressed when equal (PR #92's honest posture).

## 4. Goldens — 0 flips expected

Per PR #92's posture, today `lowest_30d == current` for **every** product (no price-update lifecycle →
P-032), so the condition is false on all real data and the line never renders. Card golden fixtures use
non-discounted / equal-price products → **no flips**. The line is exercised only by the new widget tests
(synthetic `lowest30d < price` fixtures). If a golden flips, investigate (fixture drift).

## 5. Out of scope / follow-up

- **PDP display** — the `PdpPriceBlock` slot exists but is backend-blocked: needs `lowest_30d` on the
  product-detail path (`GetByID`/`Product` + spec). Folded into the P-030 backend reach (alongside the
  P-032 price-update lifecycle), not a frontend change. Documented in the audit.
- P-032 (price-update lifecycle), P-007, P-031, chi-square flake — untouched.

## 6. Commit plan

1. this doc.
2. card: `showLowest30d` + the line (`product_card.dart`).
3. rail mapper: `lowest30dPriceMinor` in `productSummaryFromApi`.
4. tests (card: absent w/o discount, absent when `low == price`, visible when `low < price`; mapper maps the field).
5. docs closure — audit (P-030 frontend cards RESOLVED; PDP deferred), ROADMAP, REPORT.

i18n (reuse, no new key) and goldens (0 flips) are documented no-ops, not commits.
