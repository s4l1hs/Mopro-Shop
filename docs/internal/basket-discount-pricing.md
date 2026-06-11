# CT-09 — Basket discount, made real (financial path) — discovery → **DEFER (CFO/ADR-gated)**

> **Verdict: DEFER with the mapped plan below — do NOT partial-apply.** Making
> `basket_discount_pct` a charged discount is a **multi-module financial refactor**
> whose core decisions are **undefined business/CFO calls** that change
> **constitution-LOCKED (v6) cashback/commission/payout inputs** (CLAUDE.md §4.7/
> §4.8/§12). Per this lane's §1.3/§5 ("a half-applied discount is worse than the
> honest stop") and CLAUDE.md §12 ("STOP and ask the human owner" for cashback-
> formula / financial-invariant changes), the correct deliverable is this plan +
> the escalation — **not** code. No pricing code written.

## 1. Current state (confirmed)

`products.basket_discount_pct` (SMALLINT, migration **0087**, #133) drives the
"Sepette %X İndirim" **card pill only**. Grep confirms **zero** wiring in
`internal/{order,payment,cashback,sellerpayout}` — the discount is **never
applied** to any price/charge/ledger. `enrichCart` resolves
`ProductSummaryRow.BasketDiscountPct` (#178) but doesn't use it; `grand_total` =
full price sum. **The app advertises a discount it does not charge** (a real
trust/consumer-protection gap — see §6).

## 2. The pricing path (end-to-end) the discount must touch

```
cart enrichCart (grand_total)  →  payment intent (charged amount)  →
order_items snapshot (gross/commission_pct/commission_amount/kdv/seller_net, FROZEN)
   →  cashback plan (ComputePlanTerms(priceMinor, commissionBps), v6-LOCKED)
   →  seller payout (gross→net, FROZEN at delivered_at, LOCKED)
   →  double-entry ledger (every tx D==C, same currency, append-only)
```

Each node derives from **the sale price**. A discount that only moves
`grand_total` (display) without the rest = the forbidden asymmetry (§7.3 /
this lane's §5).

## 3. Invariants + financial-core conventions that apply

- **CLAUDE.md §4.1–4.6** — double-entry (D==C), single-currency per tx,
  append-only, **idempotency-key mandatory**, **transactional outbox**, integer
  minor units. Any discount needs a *balancing* ledger entry against a **defined
  funding account**.
- **§4.7 cashback (v6 LOCKED)** — `commission = round(price × commission_pct)`,
  `monthly_coin = commission × 0.50 / 12`. **`price` is the input.** Changing it to
  the discounted price **requires a new constitution version + ADR** (§4.7/§12).
- **§4.8 seller payout (LOCKED, frozen at delivered_at)** — `gross = price × qty`,
  `seller_net = gross − commission − kdv`. Property test
  (`order/property_test.go`): `commission + kdv ≤ gross ∧ seller_net ≥ 0` — must
  still hold post-discount.
- **financial-core.md** — (1) SERIALIZABLE+retry, (2) no pool-acquire-in-tx,
  (4) idempotency at storage, (5) transactional outbox, (7) soft refs / no
  cross-schema JOIN — all bind any new pricing/ledger code.

## 4. 🚩 The blocking decisions (business / CFO — NOT engineering)

The discount's **funding model is undefined**, and it determines *every*
downstream base. These are CFO/ADR calls, not code choices:

| Decision | Option A — seller-funded | Option B — Mopro-funded |
|---|---|---|
| Buyer charged | discounted | discounted |
| `gross` (seller payout) | **discounted** (seller bears it) | original (seller whole; Mopro funds gap) |
| Commission base | discounted gross | original or discounted? |
| **Cashback `price`** (v6 LOCKED) | discounted | original or discounted? |
| Ledger | clean (all on discounted) | needs a **marketing-expense** account `D equity:marketing_discount` + escrow top-up |
| Who owns `basket_discount_pct` | seller config | platform campaign |

Until A vs B is chosen (+ the cashback-`price` question answered), **any
implementation hard-codes a financial model Mopro hasn't decided** — exactly what
§12 forbids.

## 5. Phased plan (once the CFO decision + ADR land)

1. **ADR** `/docs/adr/` — funding model (A/B), commission base, cashback `price`
   base, who owns the pct. (If cashback `price` changes → constitution bump.)
2. **Schema** — an order-level discount: `order_items.discount_amount_minor`
   (+ funding-account tag), snapshotted at order time like `commission_pct_bps`.
3. **Pricing** — `enrichCart` applies the discount → discounted `grand_total` +
   a `basket_discount_minor` summary field; **payment intent charges the
   discounted total** (the asymmetry fix).
4. **Order** — snapshot the discount + the (funding-decided) gross/commission;
   keep the property invariant true.
5. **Ledger** — the funding entry per the ADR (seller-gross reduction *or*
   `equity:marketing_discount` + escrow), D==C, single-currency, outbox, idempotent.
6. **Cashback** — `ComputePlanTerms` on the ADR-decided base (constitution-aligned).
7. **Payout** — gross/net on the ADR base; property + reconcile green.
8. **UI** — "Sepette indirim" line in cart + checkout (the easy part; reuses #178).
9. **Tests** — financial property + payment/order/cashback/reconcile integration;
   idempotency replay; the asymmetry test (charged == displayed).

**General-vs-specific:** build it as a generic **order-level discount line**
(`discount_amount_minor` + a `source` tag: `basket`/`coupon`/…) so **coupon
(CT-03/CHK-04) reuses the same mechanism** — but only after the ADR.

## 6. Recommendation + escalation

- **Engineering: DEFER** — the path is a 7-module financial refactor gated on a
  CFO decision + ADR (and possibly a constitution bump for the cashback base). It
  **cannot land safely in one PR** without those, and partial-apply is barred.
- **Trust gap (for the product owner, not mine to decide):** the pill currently
  shows a discount that isn't charged. Two interim options pending the ADR —
  **(a)** hide/suppress the pill until it's real (honest now), or **(b)** expedite
  the funding ADR. The lane's anti-goal #1 says *don't hide* (parity intent), so I
  leave the pill as-is and **flag the choice to the owner** rather than silently
  pick one. CT-09 stays **DEFER** in the audit with this plan attached.
