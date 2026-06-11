# Cart/Checkout totals + discount display (CT-02/09 + CHK-01/02) — discovery

> Surface the full summary on the #176 enriched cart. Verified on
> `feat/cart-checkout-totals-completion`.

## What the enriched cart returns (#176, `cmd/core-svc/cart_enrich.go`)

`cartJSON`: `lines[]` (now with **`seller_name` + `variant_label`**), `totals_by_
seller[]` (`items_minor`, `shipping_minor`, `total_minor`), `grand_total_minor`,
`kdv_included_minor`. Mobile `CartDto`/`CartLineDto`/`SellerTotalDto` mirror it.

## Verdicts

### CHK-01 — checkout review breakdown → **UI (ship)**
The review (`checkout_review_screen.dart`) shows **total only**. All breakdown
data already flows: subtotal = Σ `items_minor`, shipping = Σ `shipping_minor`,
`kdv_included_minor`, cashback (`cartMonthlyCashbackProvider`), `grand_total`.
Pure display — mirror the cart summary. Reuses `cart.subtotal`/`shipping`/
`shipping_free`/`cashback_monthly`/`kdv_included` + `checkout.total` → **i18n 0/0**.

### CHK-02 — checkout review per-seller grouping → **UI (ship)**
`seller_name` now flows → group `lines` by `sellerId`, header = `cart.seller_section`
({seller: sellerName}) + per-seller subtotal (`totals_by_seller.items_minor`).
Mirrors the cart's `_SellerGroupHeader`. UI only.

### CT-02 — free-shipping progress → **NOT-ACTIONABLE (model divergence)**
`enrichCart` sets **`shipping_minor: 0` unconditionally** ("v1: cargo handled
separately", CLAUDE.md §2.3/§4.8) → cart shipping is **always free** ("Ücretsiz").
There is **no cart-level shipping cost and no threshold**, so "X TL daha ekle to
free shipping" has nothing to progress toward. The order-level `shipping_payer`
enum has a `threshold_free` value, but that's a *fulfillment* who-pays concept, not
a served cart threshold. Fabricating a global threshold would contradict the
always-free-cart model → **not built; documented as a divergence.**

### CT-09 — basket-discount line → **DEFER (financial, not display)**
`products.basket_discount_pct` (#133, migration 0087) is a **display-only card
pill** — grep confirms it is **NOT applied to any price/total** in
`order`/`payment`/`cart`/cashback. `enrichCart`'s `grand_total` = full price sum
(no discount). Surfacing a "Sepette indirim" line that *reduces* the total would
either **mislead** (discount shown, full price charged) or require **applying it
across pricing → order → payment → cashback** = a multi-module **financial change**
(CLAUDE.md §4 invariants), out of a display lane's scope ("no keystone work"). →
**DEFER** until the pricing path applies the basket discount; then surfacing it is
trivial. (The data — `ProductSummaryRow.BasketDiscountPct`, already resolved in
`enrichCart` — is ready for that future pricing PR.)

## Discovery shifts

1. #176 added `seller_name`/`variant_label` → CHK-02 (+ Cart CT-01-name/CT-05-label
   from the prior lane's "flagged backend") now have data.
2. **CT-02 is a divergence, not a gap** — cart shipping is unconditionally free.
3. **CT-09 is financial, not display** — `basket_discount_pct` isn't applied to
   pricing anywhere; making it a real discount line is a money change → DEFER.

## Plan (commits)

1. discovery. 2. CHK-01 review breakdown. 3. CHK-02 review per-seller grouping.
4. docs (audits + ledger): CHK-01/02 resolved; CT-02 NOT-ACTIONABLE; CT-09 DEFER.
No backend touched (CT-09 deferred) → no contract test needed; §5 N/A.
