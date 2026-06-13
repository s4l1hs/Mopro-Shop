# Membership Benefits — design + plan (financial; Wave 1)

> The financial follow-on to **AC-05** (`docs/internal/membership-tier.md`). AC-05
> shipped the tier as a **pure derived read-model** (status only, zero money
> surface) and explicitly deferred *benefits* to a later, deliberate financial
> phase. This doc designs that phase: it picks the **benefit set to ship**,
> defines **precedence/stacking** with the existing discount mechanisms, names
> every **§4/§12** invariant touched, and lays out the build plan.
>
> **Lane `feat/membership-tiers`. Migration block 0106–0107.** This is a
> financial system → **design-first**. Wave 1 = this doc only (no code). Build
> (Wave 2) follows after review. Money paths obey CLAUDE.md §4 + §12 +
> `docs/internal/financial-core.md`.

---

## 1. Current state (what AC-05 left us)

- **Tier is a derived read-model.** `internal/order/membership.go`
  (`MembershipService.GetMembershipTier`) computes a user's tier live from
  `order_schema.orders` (Σ `total_minor` + count of **delivered** orders in a
  365-day window) against `ref_schema.membership_tiers` (rank ASC ladder:
  `classic`/`gold`/`elite`, ranks 1/2/3). It stores **no balance, mints no coin,
  touches no ledger**. Served at `GET /me/membership`; the Account card renders
  badge + progress (i18n `account.tier_*`).
- **The benefit surface is empty.** A tier today confers *recognition only*. AC-05
  §6 named Phase 2 (money benefits — free-shipping, tier discount, coin
  multipliers — each "likely a §12 conversation: who funds the perk") and Phase 3
  (benefit visibility across surfaces) as deliberately deferred. This lane is that
  work.
- **The discount machinery already exists and is proven.** Two seller-funded
  discounts are live and share one seam:
  - **CT-09 basket discount** (per-product `basket_discount_pct`, migration 0091).
  - **CT-03 coupon** (cart/order-level percent code, migration 0092,
    `order_schema.coupons` + `coupon_redemptions`).
  Both flow through `internal/order/pricing.go`
  (`BasketDiscountMinor` / `DiscountedUnitMinor`, pure integer math, round-half-up)
  and `resolveCoupon`. The order build lowers `order_items.unit_price_minor` to the
  **charged** unit, and **the snapshot does the work**: commission, KDV,
  seller-net, **and cashback** all derive from that one snapshot, so **fin-svc is
  untouched, no new ledger account, the capture tx still balances**. The cart
  display path (`cmd/core-svc/cart_enrich.go`) calls the *same* helpers →
  **display == charge** by construction.

---

## 2. Benefit triage — what we can honor, and at what §-cost

Each candidate benefit mapped to an existing mechanism and its constitution cost.
The decisive question for any money benefit is **who funds it** (the coupon doc's
crux): a benefit a *seller* configures reuses the proven seller-funded seam (no
§12); a benefit *Mopro* grants to reward loyalty is **platform-funded** — a new
ledger treatment that trips **§12**.

| Candidate benefit | Backing mechanism | Funding | §12? | Verdict |
|---|---|---|---|---|
| Tier badge / recognition | AC-05 read-model | none | no | **already shipped** |
| **Tier-exclusive coupons** (a coupon usable only at/above a tier rank) | existing seller-funded coupon (0092) + one eligibility guard | seller | **no** | **SHIP — Wave 2 (simplest correct)** |
| Tier benefit *surfacing* (account "your perks", cart/checkout lock message, PDP/PLP hint) | non-financial display | none | no | **SHIP — Wave 2 (rides with the above)** |
| Tiered **free-shipping threshold** | **NONE** — see §2.1 | n/a | n/a | **NOT-ACTIONABLE** (no cost to waive) |
| Platform-funded **tier discount** (Mopro-funded % off for members) | NEW: marketing/loyalty subsidy → escrow ledger move | platform | **YES** | **DEFER → ADR** (§5 split-out) |
| **Coin / cashback multiplier** (e.g. Elite earns 1.25× monthly coin) | `internal/cashback` — the §4.7 **FROZEN** formula | platform | **YES** | **DEFER → ADR** (§5 split-out) |
| Early access / exclusive products | catalog visibility gate | none | no | possible later; non-financial, out of this lane's scope |

### 2.1 Why "tiered free shipping" is not buildable here (discovery shift)

`docs/internal/cart-checkout-totals.md` (CT-02) established that **`enrichCart`
sets `shipping_minor: 0` unconditionally** — cart shipping is *always* free ("v1:
cargo handled separately", CLAUDE.md §2.3/§4.8). There is **no cart-level shipping
cost and no threshold to progress toward.** A "free shipping for Gold+" benefit
would have **nothing to waive** — fabricating a shipping charge just to discount it
back for members would contradict the always-free-cart model and **violate §4
anti-goal #3 ("don't invent benefits with no backing mechanism")**. So the brief's
suggested "simplest = tiered shipping threshold" is *not actionable* on this
platform; the simplest correct benefit pivots to the tier-exclusive coupon (§3).

---

## 3. The benefit we ship: **tier-exclusive coupons** (seller-funded, §12-free)

A coupon may declare a **minimum tier rank**; only members at or above that rank
may apply it. This is a recognizable membership perk ("Elite üyelere özel %15
kupon") that **reuses 100% of the proven seller-funded coupon path** and adds
*only an eligibility guard* — no new discount channel, no new ledger, no §12.

### 3.1 Why this is the right "simplest correct" choice (§5 split-bailout)

- It is a **real money-path benefit** (it changes what a member is charged), so it
  exercises the exact discipline this lane exists for — yet it carries **zero new
  financial risk**: the discount itself is the *already-shipped* seller-funded
  coupon. The tier only gates **eligibility**, not the money math.
- It deliberately **creates no new stacking dimension** (see §4) — the highest-risk
  part of any benefit feature. There is still exactly **one coupon slot**; "tier
  benefit" and "coupon" are the same channel, not two that could compound.
- The two genuinely §12-laden benefits (platform-funded tier discount, coin
  multiplier) are **split out** as ADR-gated follow-ups (§6), per §5.

### 3.2 Eligibility resolution (§5-safe)

The user's tier rank is already computed **in the order module**
(`MembershipService.GetMembershipTier`, over `order_schema` + `ref_schema`). The
coupon is also applied **in the order module** (`resolveCoupon`). So the
eligibility check is **in-module** — no cross-schema JOIN, no new module
dependency. `resolveCoupon` gains the caller-supplied rank:

```go
// pure, IO-free — identically reusable by display and charge paths (display==charge)
func resolveCoupon(c *Coupon, subtotalMinor int64, redemptions, userTierRank int, now time.Time) CouponValidation {
    ...
    case userTierRank < c.MinTierRank:
        out.Reason = "tier_locked"   // NEW guard, BEFORE valid=true
    ...
}
```

Both call sites resolve the rank the same way and pass it in:
- **charge** — `Checkout` / `InitiateCheckout` (saga) resolve the buyer's tier once,
  pass the rank into the coupon resolution before freezing the snapshot.
- **display** — `cart_enrich` (`GET /cart?coupon=CODE`) resolves the same rank and
  passes it to the same `resolveCoupon` → the cart preview and the charge agree on
  eligibility. **display == charge** holds for the lock decision too, not just the
  amount.

Guest / unauthenticated / below-floor → effective **rank 1 (`classic`)**; a coupon
with `min_tier_rank = 1` (the default) is open to everyone, so **every existing
coupon is unaffected** (backward-compatible). A `min_tier_rank > 1` coupon resolves
`tier_locked` for non-members → **full price charged** (buyer-safe) → **no
redemption recorded**.

### 3.3 Data model (migration 0106)

One additive, backward-compatible column on the existing coupon table — the tier
benefit lives **next to the coupon it gates**, not in a new mapping table (the
benefit *is* the coupon's eligibility rule):

```sql
-- 0106_coupon_min_tier.up.sql  (+ init lockstep in the ecom init SQL)
ALTER TABLE order_schema.coupons
  ADD COLUMN IF NOT EXISTS min_tier_rank SMALLINT NOT NULL DEFAULT 1
      CHECK (min_tier_rank >= 1);
-- DEFAULT 1 (= classic = everyone) ⇒ existing coupons keep current behavior.
-- Dev/test seed of a tier-exclusive coupon (rank 3 = elite):
INSERT INTO order_schema.coupons (code, kind, percent_off, min_basket_minor, market, min_tier_rank, expires_at)
VALUES ('ELITE15', 'percent', 15, 0, 'TR', 3, now() + interval '10 years')
ON CONFLICT (upper(code), market) DO NOTHING;
```

- `min_tier_rank` references the **rank** (an ordinal already on
  `ref_schema.membership_tiers`), not the tier code — stable across markets and
  rename-safe; no FK across schemas (soft ordinal, §5).
- **0107 is reserved** in this lane's block for the build's incidental needs (e.g.
  an index if the seed grows, or held for the §6 follow-ups). 0106 is the only
  migration this PR requires.

### 3.4 Surfacing (account / cart / checkout)

- **Account** — the AC-05 tier card gains a small "your benefits" line per tier
  (e.g. Elite → "Sana özel kuponlar"). Pure display; no money.
- **Cart / checkout** — when a tier-exclusive coupon is applied successfully, the
  existing coupon line renders unchanged. When `tier_locked`, the existing
  invalid-coupon message path shows a localized reason ("Bu kupon yalnızca {tier}
  üyeler içindir"). No new widgets — reuses the coupon line + invalid-reason seam.
- **i18n** — new `membership.*` namespace for benefit strings (tier i18n today is
  `account.tier_*`); the **finance-facing strings get DE + AR** per the lane brief,
  plus TR + EN. The `tier_locked` reason string is finance-facing → DE/AR.

---

## 4. Precedence / stacking — the crux (display == charge after composition)

The composition rule, stated explicitly:

1. **Per-product basket discount (CT-09, seller)** applies **first, per unit** →
   `DiscountedUnitMinor(list, basketPct)`.
2. **The single coupon (CT-03, seller — tier-gated or not)** applies **per unit on
   top** of (1), exactly as today. A coupon being *tier-exclusive* changes only
   **whether** it is eligible, never **how** it composes.
3. **There is no third discount channel.** A platform-funded tier discount and a
   coin multiplier are **deferred** (§6), so this lane introduces **no new stacking
   dimension**: at most one basket discount per product + at most one coupon per
   order, as already shipped.

Because step (2) is the unchanged `resolveCoupon` → `DiscountedUnitMinor` path and
the eligibility guard runs **before** `valid=true` (it can only *withhold* the
coupon, never alter the amount), the post-composition charge is byte-identical to
today's coupon+basket charge whenever the member is eligible, and identical to the
*no-coupon* charge when locked. Therefore:

- **display == charge** — cart `grand_total_minor` (enrich, same helpers + same
  rank) == order `total_minor` (charge) == Σ(`seller_net` + `commission` + `kdv`)
  (the capture ledger balances, D==C, single currency). Proven by the CT-09/CT-03
  residual identity; unchanged here.
- **No double-application** — a tier perk *is* the coupon; it cannot stack with the
  coupon. (The platform-funded tier discount that *would* be a second channel is
  the §6 deferral precisely because composing a *second* discount channel with the
  coupon is the §4/§12-heavy problem we are not solving in this PR.)

---

## 5. §4 / §12 invariants touched

- **§4.1 / §4.2 / §4.3 (double-entry / single-currency / append-only)** — ledger
  **untouched**. Seller-funded coupon path; no new accounts; capture tx unchanged.
- **§4.4 idempotency** — redemption write is already `UNIQUE(coupon_id, order_id)`
  `ON CONFLICT DO NOTHING`; the tier guard adds **no write**. Re-checkout cannot
  double-redeem. No new cron, no new outbox event.
- **§4.6 money type** — reuses `pricing.go` integer helpers; no float.
- **§4.7 cashback** — formula **unchanged**; cashback computes on the
  coupon-discounted `unit_price_minor` snapshot, exactly as today. *(A coin
  multiplier WOULD change this → §6 / §12.)*
- **§4.8 seller payout** — `seller_net = gross − commission − kdv` on the discounted
  gross, unchanged.
- **§5 boundaries** — tier rank resolved in-module (order module owns both the tier
  read-model and coupon apply); no cross-schema JOIN; `min_tier_rank` is a soft
  ordinal, no cross-schema FK.
- **§12 — NOT triggered by the shipped benefit.** No new ledger treatment, no rate
  change, no perpetual→fixed change, no existing-plan mutation. **§12 IS triggered
  by the deferred benefits (§6)** → those are ADR-gated, not built here.

---

## 6. Deferred (§12 ADR-gated) — the platform-funded benefits, split out (§5)

These are real, desirable membership perks, but each is **Mopro-funded loyalty
spend** = a **new ledger treatment** = a CLAUDE.md §12 conversation. Per the lane
§5 split-bailout, they are **not built in this PR**; each gets its own ADR + design
checkpoint:

1. **Platform-funded tier discount.** Mopro (not the seller) absorbs a member %
   off. This is exactly the coupon doc's **Option B**: buyer-charged total <
   Σ(seller_net + commission + kdv), so Mopro must inject the gap from an
   `equity:loyalty:tier_subsidy:<currency>` → `asset:bank:escrow` move per order,
   with its own idempotency key. **New account + new capture-tx treatment →
   §12 ADR** (mirrors `docs/internal/coupon.md` §3 Option B). Composing this
   *second* discount channel with the existing coupon (precedence, double-apply
   caps) is the §4-heavy work deferred with it.
2. **Coin / cashback multiplier.** A tier that earns e.g. 1.25× monthly coin
   changes the **§4.7 FROZEN** cashback formula and the per-plan snapshot — a
   constitution change requiring a **new constitution version + ADR** (CLAUDE.md
   §12). Existing plans are immutable; only NEW plans could carry a multiplier, and
   only with CFO approval.

When wanted, each starts as its own discovery doc + `/docs/adr/` entry; do not bolt
either onto this PR.

---

## 7. Build plan (Wave 2 — one commit per concern)

1. **model + migration** — `order_schema.coupons.min_tier_rank` (0106 + init
   lockstep); `Coupon.MinTierRank` domain field; repository scan/insert carries it;
   seed `ELITE15`.
2. **eligibility resolution** — `resolveCoupon` gains `userTierRank` + the
   `tier_locked` guard; `Checkout` / `InitiateCheckout` (saga) and `cart_enrich`
   resolve the buyer's tier (in-module `MembershipService`) and pass the rank →
   same guard both sides (display == charge).
3. **surfacing** — account "your benefits" line; cart/checkout `tier_locked`
   message; `membership.*` i18n (TR/EN; **DE/AR** for the finance-facing
   `tier_locked` string).
4. **spec + codegen** — add `min_tier_rank` to the coupon-validate response /
   coupon fields as needed; regen in this lane's Wave-2 codegen slot; `flutter
   analyze` 0.
5. **tests** — see §8.

---

## 8. Test plan (DoD §6)

- **Composition / display == charge (the key test):** basket discount + a
  tier-exclusive coupon, eligible member → cart `grand_total` == order `total` ==
  Σ(seller_net + commission + kdv). Integer-exact; ledger balances.
- **Eligibility:** below-rank user (and guest) → `tier_locked`, full price charged,
  **no redemption row**; at/above-rank user → coupon applies.
- **Idempotency:** re-run capture with the same idempotency key → no second
  redemption, no double discount.
- **Backward-compat:** a `min_tier_rank = 1` coupon behaves exactly as a pre-0106
  coupon for all users.
- Contract test for any new/changed coupon-validate field (the `cmd/core-svc`
  live-handler conformance pattern).

## 9. Definition of Done (lane §6)

- [x] **Design doc** — benefit set, precedence/stacking, data model, §4/§12 flags,
      build plan; ADR triggers identified (§6). *(Wave 1)*
- [x] Tier→benefit (min-tier coupon) model + resolution composing correctly with
      basket discount + coupon; account/cart surfacing. *(Wave 2)*
- [x] Composition test proves display == charge; idempotency + eligibility tested.
- [x] §4 + §5 + boundaries + i18n green; **codegen NONE** (coupons not in spec →
      no `.gen` change → no #87 serialization collision). PR opened.

### Build outcome (Wave 2)

Shipped exactly the approved design. Migration **0106** (`coupons.min_tier_rank
SMALLINT NOT NULL DEFAULT 1`, additive/backward-compatible, seeds `ELITE15` rank 3;
0107 reserved). `resolveCoupon` gained a `userTierRank` arg + a `tier_locked` guard
that runs **before** `Valid=true` — eligibility only, amount path untouched. Tier
rank resolved in-module via `order.MembershipService` (`orderService.tierRank`,
fail-closed → rank 1 on nil/guest/error), threaded into both money paths
(`resolveCouponForCharge` for Checkout + saga) and the display path
(`ValidateCoupon(...,userID)` ← `cart_enrich` passes `c.UserID`), so the lock
decision can't diverge between cart preview and charge. `NewServiceFull` gained an
optional `membership` param (wired in `cmd/core-svc/main.go`); the legacy
`NewService` path leaves it nil (→ rank 1). Surfacing: account "your benefits" line
(rank > 1) + cart `membership.coupon_tier_locked` message; i18n TR/EN/DE/AR.

**Discovery shifts:** (1) **no codegen** — coupons are hand-written raw-Dio, not in
`api/openapi.yaml`; the `tier_locked` reason rides the existing hand-written cart
JSON `coupon_message`, so nothing crossed the generated surface and the #87 regen
lane is untouched. (2) no init lockstep — the `coupons` table lives only in
migration 0092 (not in `deploy/postgres-ecom/init`), so 0106 is migration-only.
(3) composition held with **zero** new stacking: the gate withholds, never alters,
so basket+coupon math is byte-identical to pre-0106 whenever eligible.

## 10. Discovery shifts (for the report)

- **Free-shipping benefit is not actionable** (CT-02: cart shipping is
  unconditionally free → nothing to waive) → simplest benefit pivots from the
  brief's suggested shipping threshold to the **tier-exclusive coupon**.
- **Tier eligibility is §5-trivial** — both the tier read-model and coupon apply
  already live in the **order module**, so gating one on the other needs no new
  cross-module/cross-schema path.
- **The shipped benefit creates no new stacking dimension** — a tier-exclusive
  coupon *is* the single coupon slot, so display==charge and no-double-apply hold
  by construction; the genuinely stacking benefits (platform-funded discount, coin
  multiplier) are the §12 split-outs.
- **§12 fires only on funding.** A seller-funded perk reuses the proven seam
  (no §12); a Mopro-funded perk (tier discount, coin multiplier) is a new ledger
  treatment / a §4.7 change → ADR-gated.

## 11. References

- `docs/internal/membership-tier.md` (AC-05 — tier read-model, phase plan).
- `internal/order/membership.go` — `MembershipService` (tier rank source).
- `internal/order/coupon.go` / `pricing.go` — coupon resolve + pure discount
  helpers (the reused seam).
- `docs/internal/coupon.md` (CT-03 — funding model; Option A seller-funded shipped,
  Option B platform-funded = §12), `docs/internal/basket-discount-pricing.md`
  (CT-09), `docs/internal/cart-checkout-totals.md` (CT-02 free-shipping divergence).
- `migrations/ecom/0092_coupons.up.sql`; this lane → `0106_coupon_min_tier`.
- `docs/internal/financial-core.md` §4; `CLAUDE.md` §4 / §5 / §12.
</content>
</invoke>
