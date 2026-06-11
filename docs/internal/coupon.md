# Coupon Apply/Validate — Discovery (CT-03 / CHK-04)

> **Discovery doc — no code applied yet.** Financial-path lane. This documents the
> current state, the reusable CT-09 mechanism, and **the funding-model decision that
> gates implementation**. Per the lane brief: *do not apply a discount until Salih
> confirms the funding model.* If the confirmed model needs new ledger accounting,
> `CLAUDE.md §12` triggers → STOP + DEFER (this doc records the plan).

---

## 1. What exists today

**Backend: nothing.** There is **no coupon/promo/voucher model** anywhere —
no table (`migrations/ecom` tops out at `0091`; no `coupon`/`promo`/`voucher`
DDL), no validation, no endpoint, no event. The `coupon`/`promo` grep hits in
`internal/` are all CT-09 *basket-discount* code and an unrelated mega-menu
`promo_image_placeholder`.

**Mobile: a desktop-only placeholder (CT-03).** `OrderSummaryCard`
(`mobile/lib/features/cart/widgets/order_summary_card.dart`) renders a coupon
`TextField` + an **inert** "Uygula" button:

```dart
onPressed: () {}, // coupon backend not wired (REPORT §4)
```

The doc comment is honest: *"Coupon application is a placeholder (no coupon
backend exists yet)."* Mobile cart (`CartTotalsSummary`) has **no** coupon entry
at all; checkout (`CheckoutReviewScreen`) has none either (CHK-04 is "absent").

**Audit status:** Cart **CT-03** (placeholder, no backend, desktop-only) +
Checkout **CHK-04** (absent) — both MED, flagged as the shared backend cluster
alongside the now-resolved CT-09.

---

## 2. The CT-09 mechanism to reuse (`internal/order/pricing.go`)

CT-09 (PR #180, migration 0091) made the seller-funded "Sepette %X İndirim" a
**charged** discount. The whole apparatus already anticipates the coupon — the
file header says so:

> *"Coupon (CT-03/CHK-04) reuses `BasketDiscountMinor` for its own percentage
> line; the order carries a single `discount_minor` aggregate either source feeds."*

The two pure helpers (integer math, round-half-up in the buyer's favour, no float
per §4.6):

```go
BasketDiscountMinor(baseMinor int64, pct int) int64   // discount amount
DiscountedUnitMinor(unitPriceMinor int64, pct int) int64 // charged unit = base − discount
```

**Why this is the right seam — "the snapshot does the work":**

1. **Order build** (`internal/order/service.go` `Checkout`, `internal/order/saga.go`
   `InitiateCheckout`) applies the discount **per unit**, so
   `order_items.unit_price_minor` *is the charged unit*. Commission, KDV, and
   seller-net are then frozen on the **discounted** gross:
   ```
   discUnit  = DiscountedUnitMinor(v.PriceMinor, pct)
   gross     = discUnit * qty
   commAmt   = gross * commissionPctBps / 10000
   kdvAmt    = commAmt * kdvPctBps / 10000
   sellerNet = gross − commAmt − kdvAmt
   ```
2. **Cart display** (`cmd/core-svc/cart_enrich.go`) calls the *same*
   `DiscountedUnitMinor` → the price shown can never diverge from the price
   charged (the display==charge / asymmetry rule).
3. **Downstream is automatic.** `orders.discount_minor` = Σ(list−discounted)×qty
   (the summary line). The `ecom.order.delivered.v1` payload carries the per-item
   snapshot; **cashback** (`internal/cashback/consumer.go`) reads
   `unit_price_minor` and computes the monthly coin on the **discounted** price —
   `fin-svc is untouched`. The capture ledger balances because buyer-charged total
   == Σ(seller_net + commission + kdv).

So a **seller-funded** coupon needs *no fin-svc change and no new ledger account* —
exactly the CT-09 outcome.

---

## 3. The funding-model decision (the crux — for Salih)

A coupon is an **order/cart-level code** (percent or fixed amount), unlike CT-09
which is a **per-product** seller attribute. Who absorbs the discount changes the
money math fundamentally:

### Option A — Seller-funded (mirrors CT-09)
- The discount **reduces seller-net.** Distribute the coupon across the line items
  (largest-remainder, to avoid rounding drift) and lower each `unit_price_minor`
  snapshot — exactly the CT-09 path.
- Commission, KDV, seller-net, **and cashback all compute on the discounted
  price** (the snapshot does the work).
- Capture ledger balances unchanged. **No constitution change, no new accounts,
  fin-svc untouched.** Reuses 100% of the CT-09 mechanism.
- **Natural fit:** a coupon scoped to one seller. A *cross-seller* cart-level
  coupon is awkward here — which seller funds it? (Would have to split across the
  per-seller orders the saga already produces.)

### Option B — Platform-funded (marketing expense)
- The discount is **Mopro's marketing cost**, NOT a seller-net reduction. The
  seller still receives full net; commission and **cashback compute on the
  *pre-coupon* price** (the buyer keeps full cashback — arguably on-brand).
- But then **buyer-charged total (subtotal − coupon) < Σ(seller_net + commission
  + kdv)**. The gap = the coupon amount must be **injected by Mopro** from a
  marketing-expense / equity account into escrow so the capture transaction still
  balances double-entry (§4.1).
- That is a **new ledger treatment** (a `equity:marketing:coupon_subsidy` →
  `asset:bank:escrow` move per redemption, with its own idempotency key). New
  financial accounting that isn't in the constitution.
- **⚠️ This trips `CLAUDE.md §12`** ("introduce a new ledger treatment" /
  "improvise new financial accounting"). Per the lane's §5 split-bailout and §7
  anti-goals, **Option B = STOP + DEFER**: write up the ADR (new account, the
  capture-tx change, the redemption ledger move, idempotency) and get explicit
  approval before any code. We do **not** invent this accounting in this PR.

### Recommendation
**Option A (seller-funded)**, mirroring the CT-09 decision Salih already made for
basket discounts. It ships now with zero financial risk and reuses the proven
seam. Scope the first coupon to **percent or fixed-amount, single funding source,
no stacking** (§5: ship simple validate+apply first). If a marketing/platform
coupon is wanted, that is a separate ADR-gated effort (Option B).

---

## 4. Proposed model (pending funding confirmation)

A minimal coupon for the simple case (seed test coupons — creation/admin is out of
scope):

```
ref_schema.coupons  (or coupon_schema — TBD; ref_schema if globally readable like categories)
  id              BIGINT PK
  code            TEXT UNIQUE (case-insensitive)
  kind            TEXT   -- 'percent' | 'amount'
  value           INT    -- percent (1..100) OR amount_minor
  currency        TEXT   -- for 'amount' kind; validated vs ref_schema.currencies
  min_basket_minor BIGINT DEFAULT 0
  scope           TEXT   -- 'cart' | 'seller:<id>' | 'category:<id>'  (start: 'cart')
  funding         TEXT   -- 'seller' | 'platform'  (Option A ⇒ only 'seller' for now)
  starts_at, expires_at TIMESTAMPTZ
  max_redemptions, per_user_limit INT NULL
  active          BOOL DEFAULT true
  market          TEXT
```

**Validation** (`code → valid?`) checks: exists, active, within window, market
match, `subtotal ≥ min_basket_minor`, redemption limits. A **read** — no
idempotency needed.

**Apply** is where it lands on the order. For Option A the *financial* write is
still the existing order capture (already idempotent via the order idempotency
key); the coupon just feeds the per-unit distribution into the existing snapshot
path. **Redemption tracking** (usage-limit decrement) is the new financial-ish
write and MUST be idempotent: a `coupon_redemptions(coupon_id, order_id)` row with
a **UNIQUE (coupon_id, order_id)** + `ON CONFLICT DO NOTHING` (financial-core §4),
so a retried capture can't double-count a redemption.

**Idempotency surface (financial-core §4):** redemption insert is UNIQUE-keyed;
no new cron; no new outbox event for Option A (the order/delivered event already
carries the discounted snapshot).

---

## 5. Decision log

- [x] **Funding model — SELLER-FUNDED (Salih-confirmed, Option A).** Mirrors the
      CT-09 basket-discount decision. No constitution change, no new ledger account,
      fin-svc untouched.
- [x] **Implemented (v1 = percent, cart-level):**
  - migration `0092`: `order_schema.coupons` + `coupon_redemptions`
    (UNIQUE(coupon_id, order_id) ⇒ idempotent redemption, financial-core §4) +
    `orders.coupon_code` / `coupon_discount_minor`; seed `WELCOME10`/`SAVE20`.
  - `internal/order/coupon.go`: `Coupon` + pure `resolveCoupon` guards
    (active/window/min-basket/redemption) + `CouponRedemption`.
  - `order.Service.ValidateCoupon` (read preview) + Repository coupon methods.
  - `Checkout` + `InitiateCheckout` (saga): two-pass build resolves the coupon
    against the basket-discounted subtotal, applies `couponPct` **per unit on top
    of** the CT-09 basket discount → `order_items.unit_price_minor` is the final
    CHARGED unit → commission/KDV/seller-net/cashback all derive from it. Redemption
    recorded in the same tx.
  - Display: `GET /cart?coupon=CODE` (`cart_enrich`) applies the same resolve logic
    ⇒ **display==charge**; carry-through via `/checkout/initiate` + legacy
    `/orders/checkout` body `coupon_code`.
  - Mobile: cart `applyCoupon` + coupon line + invalid message; checkout sends the
    code.
- **Edge handling:** a stale/expired code at charge time is silently dropped (charge
  full = buyer-safe). A multi-seller cart-level coupon records one redemption per
  seller-order (conservative — counts ≥, never <, so max-redemptions can't be
  exceeded).
- **Deferred (follow-ups, not v1):** fixed-amount coupons (need largest-remainder
  distribution across lines), coupon *creation*/admin, stacking rules beyond
  basket+single-coupon, scope=seller/category. Option B (platform-funded) remains
  ADR-gated (§12) if ever wanted.

---

## 6. References
- `internal/order/pricing.go` — the reusable helpers (CT-09).
- `internal/order/service.go` / `saga.go` — the per-unit snapshot application.
- `cmd/core-svc/cart_enrich.go` — display side (same helper → display==charge).
- `internal/cashback/consumer.go` — reads `unit_price_minor` snapshot (why
  seller-funded needs no fin-svc change).
- `docs/internal/financial-core.md` §4 (idempotency), `CLAUDE.md` §4 / §12.
- `docs/internal/basket-discount-pricing.md` (CT-09), migration `0091`.
- Audits: `TRENDYOL_PARITY_CART_AUDIT.md` (CT-03), `TRENDYOL_PARITY_CHECKOUT_AUDIT.md` (CHK-04).
</content>
