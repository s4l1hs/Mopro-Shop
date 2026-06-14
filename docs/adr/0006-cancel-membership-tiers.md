# ADR 0006: Cancel Membership Tiers — Cashback/Coin is the Sole Loyalty Mechanism

- **Status:** Accepted
- **Date:** 2026-06-14
- **Phase introduced:** Parity / loyalty-model consolidation
- **Decided by:** Salih (project owner) — supersedes AC-05 (tier read-model) and the
  #222 "Membership benefits Wave 2" (tier-exclusive coupons)
- **Related:** CLAUDE.md §1 (perpetual cashback business model), §4.7 (cashback engine,
  FROZEN), §12 (money-adjacent change escalation); `docs/internal/membership-teardown.md`;
  migrations 0094 (membership_tiers), 0106 (coupon min_tier_rank), 0107 (drop-forward)

## Context

Two increments built a membership-tier ("classic/gold/elite") loyalty layer:

- **AC-05** — a derived membership read-model (`order.MembershipService`) computed
  per-request from delivered-order spend/count over a rolling window against a
  `ref_schema.membership_tiers` ladder, surfaced as a badge/progress card on Account
  and a `GET /me/membership` endpoint. **It stored no balance, minted no coin, and
  never touched postgres-ledger.**
- **#222** — tier-exclusive coupons: a `min_tier_rank` eligibility gate on
  `order_schema.coupons`. This was an *eligibility* gate only (it could withhold a
  coupon but never change an amount), so it was amount-neutral and §12-free by
  construction.

The product direction is that **Mopro's loyalty is the perpetual cashback/coin
mechanism** (CLAUDE.md §1, §4.7) — a single, legible value story. A parallel tiering
system dilutes that, adds a second loyalty surface to reason about, and creates future
pressure to attach money to tiers (tier subsidies, cashback multipliers — the very
§12-deferred items #222 flagged). Rather than carry that scaffolding, tiers are
cancelled.

## Decision

1. **Remove all membership-tier structures** — AC-05 (`MembershipService`, the tier
   read-model, the Account card, `GET /me/membership`, the `Membership` spec schema)
   and #222 (the `min_tier_rank` coupon gate + its surfacing). Coupons resolve exactly
   as pre-#222 (every coupon available to everyone, subject to the existing
   active/window/min-basket/redemption checks).
2. **Cashback/coin is the sole loyalty mechanism.** No replacement tier system.
3. **The cashback/coin ledger is untouched** — accounts, the §4.7 frozen formula, and
   all financial invariants are byte-for-byte unchanged. This teardown removed a tier
   read-model and an amount-neutral coupon gate; **no money path changed**, so
   display==charge and ledger balance/idempotency are preserved trivially.
4. **`ELITE15` (the rank-3 demo coupon) is deleted, not un-gated.** Un-gating would
   silently convert an elite-only 15%-off demo into an everyone promo; deletion keeps
   the live coupon set unchanged in *effect*.

## §12 note

§12 escalation applies to changes that touch the ledger / cashback engine / seller
payout / money math. This change is **money-adjacent but not money-altering**: the
removed tier gate was amount-neutral, and the cashback ledger is not touched. The
decision is nonetheless recorded here as the brief requires, and to make explicit that
**coin/cashback is, by decision, the only loyalty channel** going forward. Re-introducing
tiers — especially any tier that attaches money (subsidy, cashback multiplier) — requires
a new ADR and §12 review.

## Consequences

- **Expand/contract:** the destructive schema drop is a separate forward migration
  (0107) gated behind removing the tier-reading code; its down-migration recreates the
  scaffolding (additive) for rollback. Deploy must land the new image before/with the
  0107 drop (RUNBOOK §5 migration checkpoint).
- 0094/0106 remain in history (never rewritten); 0107 reverses them forward.
- Fresh-DB init (`deploy/postgres-ecom/init/40-ref-schema.sql`, `50-ref-seed.sql`) drops
  the `membership_tiers` table/seed to stay in lockstep with the post-0107 end state.
