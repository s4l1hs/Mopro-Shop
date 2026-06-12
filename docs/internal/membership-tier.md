# AC-05 — Membership Tier: design + phased plan

A Trendyol-style membership tier (qualify by 12-month shopping activity →
status + benefits) **designed to coexist with** — not replace — Mopro's coin +
active-plans model. Design-first; **phase 1** ships in this PR.

## 1. The coexistence story (the §1.3 question)

**Mopro's existing loyalty IS the coin model:** every purchase creates a
perpetual cashback plan (monthly TRY_COIN forever, §4.7). It is *transactional*
loyalty — reward proportional to each individual purchase, paid in a
money-adjacent instrument, governed by the financial core.

**A tier is a different axis: *status* loyalty.** It is computed from
*cumulative* activity (12-month spend + order count), confers *recognition +
(later) privileges*, and pays out nothing per-purchase. The two relate without
overlapping:

| | Coin / plans (existing) | Tier (this design) |
|---|---|---|
| Trigger | each delivered order | cumulative 12-month activity |
| Payout | monthly TRY_COIN, perpetual | status (badge), later perks |
| Nature | financial (ledger, §4) | **derived read-model — no ledger, no balance** |
| Mutates money? | yes (wallet credits) | **never** (phase 1); money perks = financial follow-ups |

**Recommendation: coexist, with a hard wall.** The tier is a *pure derivation*
over order history — it stores no balance, mints no coin, never touches
postgres-ledger. The shared narrative: *coin rewards every purchase; the tier
rewards being a regular.* They reinforce: higher activity → both more plans
**and** higher tier. The wall: any tier *benefit* that changes money (free
shipping, tier discount, bonus coin multipliers) is a **financial change**
(§4 / financial-core) and is **deferred to its own phase** — phase 1 is
read-only and cannot create a §12 question. (Salih has decided to build the
tier; this section is the coherence story, and the design honors it by keeping
the tier strictly non-financial until a deliberate financial phase.)

## 2. Tier model (data-driven, not hardcoded)

Tiers are **reference data**, not code constants (CLAUDE.md §2.2/§10-11: no
hardcoded market/currency/thresholds). New table **`ref_schema.membership_tiers`**
(migration `0094`; ref_schema is SELECT-able by every module and has
default-privilege auto-grants):

```
code TEXT  · rank INT  · market TEXT  · currency TEXT
min_spend_minor BIGINT · min_orders INT · active BOOL
```

TR launch seed (windowed over 365 days, thresholds AND-ed):

| code | rank | min spend | min orders |
|---|---|---|---|
| `classic` | 1 | 0 | 0 |
| `gold` | 2 | ₺2.500 (250000) | 5 |
| `elite` | 3 | ₺10.000 (1000000) | 15 |

Adding a market = new rows (zero code change). Tier **codes** travel over the
API; the client localizes display names (`account.tier_classic` …) — no
hardcoded TR strings server-side.

## 3. Computation (§5-safe path)

Qualifying activity = **delivered** orders in the last **365 days** (cancelled /
refunded excluded; deterministic and snapshot-friendly). Spend = Σ
`orders.total_minor` of those orders, in the order currency.

**Where it lives:** the **order module** owns `order_schema.orders`, so the
aggregation is a single-schema query there — no cross-schema JOIN.
`ref_schema.membership_tiers` is read by the same module (ref_schema is the
explicitly allowed shared-read exception, §5). Following the module's own
established pattern (**`ReturnService` was kept separate from `Service` so the
existing order mocks stay untouched**), the tier surface is a separate
interface:

```go
// internal/order/membership.go
type MembershipService interface {
    GetMembershipTier(ctx, userID, market) (Membership, error)
}
// repo adds: UserOrderStats(ctx, userID, since) (spendMinor, count, err)
//            ListMembershipTiers(ctx, market) ([]MembershipTierDef, err)
```

Derivation: highest-rank tier whose `min_spend_minor` **and** `min_orders` are
both met; `next_*` fields describe the next rank (omitted at top tier). Live
computation per request (cheap: one indexed aggregate over a user's orders +
one tiny ref read). A materialized snapshot is a later optimization, not needed
at launch volume.

## 4. API + clients (codegen)

`GET /me/membership` (requireAuth, tag `[me]` → lands in the generated `MeApi`):

```json
{ "tier": "gold", "rank": 2, "window_days": 365,
  "spend_minor": 412000, "order_count": 7, "currency": "TRY",
  "next_tier": "elite", "next_min_spend_minor": 1000000, "next_min_orders": 15 }
```

`tier`/`next_tier` are **plain strings** (ref data — an enum in the spec would
re-hardcode the tier set). Contract test: live-handler conformance against the
`Membership` schema (the established `cmd/core-svc` pattern).

## 5. Account UI (phase 1)

A tier card in the Account header under the stat tiles: badge (tier icon +
localized name) + **progress to the next tier** — progress = the *binding*
constraint (`min(spend/next_spend, orders/next_orders)` — both must be met) — +
a caption with the remaining spend/orders ("Elite için ₺X harcama, Y sipariş
kaldı"). Top tier shows a "highest tier" state, no bar. Hidden for guests
(the header already gates on auth).

## 6. Phases

- **Phase 1 (this PR):** migration 0094 (+ init lockstep) → `MembershipService`
  (order module, §5-safe) → spec + codegen → `GET /me/membership` handler +
  contract test → Account tier card + i18n + tests. **Read-only; zero financial
  surface.**
- **Phase 2 (deferred, financial):** money benefits — tier free-shipping, tier
  discounts, coin multipliers. Each is a §4/financial-core change (pricing →
  order → payout asymmetry guards) and likely a §12 conversation (who funds the
  perk). Explicitly NOT bolted onto phase 1.
- **Phase 3 (deferred, product):** benefit enforcement/visibility across
  surfaces (PLP/PDP/checkout tier flags), tier-change notifications, seller-side
  visibility.

## Discovery shifts
- The order module's own `ReturnService` precedent makes the separate-interface
  choice free (no fake/mock breakage across the 3 Go stub sites).
- `ref_schema` default privileges auto-grant SELECT on new tables → the
  migration needs no per-role grant block.
- The tier computation never needs identity/wallet data — order_schema +
  ref_schema alone → genuinely §5-trivial.
