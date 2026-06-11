# CT-09 — Basket discount, made real (financial path) — **seller-funded, IMPLEMENT**

> **Verdict: IMPLEMENT under the seller-funded model — landable in one PR with no
> constitution change and no new ledger accounts.** This supersedes the earlier
> DEFER verdict (commit `88df133f`). The prior discovery deferred because it
> treated the *funding model* as an undefined CFO call and read feeding the
> discounted price to cashback as a §4.7 constitution change. Re-examination shows
> neither blocker survives once the obvious model is named: `basket_discount_pct`
> lives on `products` (a **seller-owned** attribute, exactly like Trendyol's
> "Sepette indirim"), so it is **definitionally seller-funded**. Owner confirmed
> seller-funded. No pricing code was written before this decision.

## 1. Current state (confirmed)

`products.basket_discount_pct` (SMALLINT, migration **0087**, #133) drives the
"Sepette %X İndirim" **card pill only**. Grep confirms **zero** wiring in
`internal/{order,payment,cashback,sellerpayout}` — the discount is **never
applied** to any price/charge/ledger. `enrichCart` resolves
`ProductSummaryRow.BasketDiscountPct` (#178) but doesn't use it; `grand_total` is
the full price sum. **The app advertises a discount it does not charge** — a
trust/consumer-protection gap. This lane closes it by *charging* the discount.

## 2. The pricing path (end-to-end) and the one place we change it

```
cart enrichCart (grand_total)  →  payment intent (charged amount)  →
order_items snapshot (unit_price/commission_pct/commission_amount/kdv/seller_net, FROZEN)
   →  cashback plan (ComputePlanTerms(priceMinor, commissionBps))
   →  seller payout (gross→net, FROZEN at delivered_at)
   →  double-entry ledger (every tx D==C, same currency, append-only)
```

**Discovery shift — the snapshot does the work.** Every fin-svc node derives from
the **`order_items` snapshot** the order build freezes at checkout:

- cashback `priceMinor` = `Σ(unit_price_minor × qty)` (cashback/consumer.go:78, the
  backward-compat path core-svc actually takes — `PriceMinor`/`CommissionBps` are
  not set on the delivered event).
- orderledger `GrossMinor` = `order.total_minor` (orderledger/consumer.go:83), and
  per-line `commission_amount_minor` / `seller_net_minor` / `kdv_amount_minor`.
- sellerpayout reads `seller_net_minor` (sellerpayout/consumer.go).
- seller breakdown computes `gross = unit_price_minor × qty`.
- returns refund = `unit_price_minor × qty` (order/returns.go:251).

So if the order build makes **`unit_price_minor` the discounted (effective) unit
price** and freezes commission/KDV/seller-net on the discounted gross, **every
downstream consumer inherits the discount with zero code change**, and the ledger
still balances exactly:

```
GrossMinor = total_minor = Σ(discountedUnit × qty)
per line: commission + kdv + seller_net = discountedGross   (seller_net = gross − comm − kdv)
⇒ commission_revenue residual = total − Σseller_net − Σkdv − shipping(0) = Σcommission   (D==C)
```

**fin-svc is therefore untouched.** All change is concentrated in the core-svc
order build + the display surfaces.

## 3. Invariants + financial-core conventions honored

- **§4.1 double-entry / §4.2 single-currency / §4.3 append-only** — unchanged; the
  capture entry still balances (the residual proof above). No new accounts.
- **§4.4 idempotency** — order build is already idempotent (`FindByIdempotencyKey`
  / per-seller `idemKey`); the discount is computed *inside* that same path, adding
  no new write surface.
- **§4.6 integer minor units** — the discount helper is pure integer math
  (`order/pricing.go`, round-half-up), never float.
- **§4.7 cashback (v6/v8)** — the **formula is unchanged**. `price` was always "the
  price the item sold for"; under a seller-funded basket discount the item *sells
  for* the discounted price, so the snapshot price is the discounted price. No rate
  change, no perpetual→fixed change, no existing-plan mutation → **not** a
  constitution change (CLAUDE.md §12 triggers do not fire).
- **§4.8 seller payout** — `seller_net = gross − commission − kdv` on the
  discounted gross; the property invariant (`seller_net ≥ 0`,
  `commission + kdv ≤ gross`) holds because it is the same formula on a *smaller*
  gross. The seller bears the discount they configured on their product.
- **financial-core.md** — (4) idempotency at storage, (5) transactional outbox,
  (7) soft refs / no cross-schema JOIN: no new ledger writes are added, so (1)/(2)
  are not newly engaged; (7) the pct is read via the catalog `Service` seam (no
  JOIN across schemas in core-svc).

## 4. Architecture decided

- **Funding: seller-funded.** The seller configures `products.basket_discount_pct`;
  the discount reduces the effective sale price; commission, KDV, seller-net,
  cashback price, payment total and ledger all compute on the discounted price via
  the snapshot.
- **Representation (audit-preserving):**
  - `order_items.unit_price_minor` = the **discounted** effective unit (what the
    buyer is charged; the snapshot base for all downstream math).
  - `order_items.list_unit_price_minor` (new) = the pre-basket-discount unit
    (= `variant.price_minor`) — for the strikethrough + the "Sepette indirim" delta.
  - `order_items.basket_discount_pct` (new) = the snapshotted whole-percent rate.
  - `orders.discount_minor` (new) = `Σ(list − discounted)×qty`; `subtotal_minor` =
    pre-discount sum; `total_minor` = `subtotal − discount` (= charged). For
    non-discounted orders `discount = 0` and `subtotal == total` (no behavior change).
- **Display==charge guarantee.** `enrichCart` (display) and the order build (charge)
  call the **same** pure helper `order.DiscountedUnitMinor(unit, pct)`, so the cart
  total and the PSP charge can never diverge (this lane's §5 asymmetry rule).
- **pct source.** `basket_discount_pct` is surfaced on `catalog.Variant`
  (`GetVariantByID` already JOINs `products`) — the order build already resolves the
  variant per line, so no new catalog interface method (and no fake churn). `enrichCart`
  keeps using `ProductSummaryRow.BasketDiscountPct`; both read the same column.
- **General-vs-specific / coupon reuse.** The pure helper is `BasketDiscountMinor
  (base, pct)` + `DiscountedUnitMinor`, and the order carries a single
  `discount_minor` aggregate. Coupon (CT-03/CHK-04) reuses the same helper and the
  same `orders.discount_minor` line; a per-line `source` tag can be added when coupon
  lands (basket is per-line/seller-configured; coupon is cart-level/code-driven).

## 5. What ships

1. **catalog** — `Variant.BasketDiscountPct *int`, populated by `GetVariantByID`.
2. **schema** — migration `0091_order_basket_discount` + init `65-order-schema.sql`:
   `order_items.list_unit_price_minor`, `order_items.basket_discount_pct`,
   `orders.discount_minor` (all `DEFAULT 0`, backward-compatible).
3. **order pricing** — `order/pricing.go` (pure helper); `Checkout` + the
   `InitiateCheckout` saga apply the per-unit discount, freeze the discounted
   snapshot, and set `subtotal/discount/total`; repository INSERT/scan carry the
   new columns; domain structs gain the fields.
4. **display** — `enrichCart` charges the discounted line price + emits a
   `basket_discount_minor` summary line; the seller breakdown surfaces list/discount
   for transparency while reconciling on the discounted gross.
5. **mobile** — cart DTO + summary render the "Sepette indirim" line.
6. **tests + audits** — order/cart property + integration; the asymmetry test
   (charged == displayed); CT-09 → RESOLVED.

## 6. Ledger note — coupon (CT-03/CHK-04) extends this seam

The coupon discount (`docs/internal/coupon.md`, migration `0092`) is **also
seller-funded** and reuses this exact mechanism: `order/pricing.go`
`DiscountedUnitMinor` is applied a second time, **per unit, on top of** the basket
discount, so `order_items.unit_price_minor` remains the single charged-unit
snapshot every downstream consumer derives from. Therefore the coupon — like the
basket discount — needs **no new ledger account and no fin-svc change**: the capture
move still balances (buyer-charged total == Σ seller_net+commission+kdv) and cashback
computes on the coupon-discounted price. The only new persistence is
`order_schema.coupon_redemptions` (idempotent usage tracking, financial-core §4) —
not a ledger account. `orders.discount_minor` now aggregates basket + coupon;
`orders.coupon_discount_minor` carries the coupon slice for the summary line.
</content>
</invoke>
