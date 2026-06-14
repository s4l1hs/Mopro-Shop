# Membership-Tier Teardown — remove #222 + AC-05 (cancelled)

> Branch `chore/remove-membership-tiers`. Membership tiering is cancelled;
> **cashback/coin is the sole loyalty mechanism**. Remove all tier scaffolding
> cleanly. **The cashback/coin ledger and its §4.7 invariants are NOT touched.**
> Existing non-tier coupons keep working. Local-verify; deploy deferred.

## Decision summary
- **§12 / ADR:** the cancellation is recorded in `docs/adr/0006-cancel-membership-tiers.md`
  (money-adjacent feature removed; coin/cashback is deliberately the only loyalty
  channel). The ledger is untouched, so no ledger ADR is required — but the *product*
  decision is ADR-worthy and is recorded.
- **Prod gated-coupon decision: DELETE `ELITE15`** (do NOT un-gate). `ELITE15` is a
  rank-3 *demo/dev* coupon seeded inside migration 0106 (its own comment: "Dev/test
  seed … harmless in prod (a demo code)"). Un-gating (rank→1) would silently widen a
  15%-off promo to everyone — forbidden by the brief. The drop-forward migration
  deletes it before dropping the gate column; the down-migration recreates it.
- **Expand/contract:** code (tier reads) out first; the destructive schema drop is a
  separate forward migration (**0107**, NOT a rewrite of 0094/0106) whose down is
  additive. Deploy must run the new image before/with `ledger…ecom up` to 0107 —
  flagged for RUNBOOK §5.

## Inventory + disposition

### #222 — tier-exclusive coupon gate
| Ref | Disposition |
|---|---|
| `internal/order/coupon.go` — `Coupon.MinTierRank`, `resolveCoupon` `userTierRank` param + `tier_locked` case + Reason doc | Remove field, param, case; coupon resolution reverts to exactly pre-#222 |
| `internal/order/service.go` — `tierRank()`, `membership` field, `resolveCouponForCharge`/`ValidateCoupon` `userID` threading + `NewServiceFull` `membership` param | Remove `tierRank`; drop `userID` from `ValidateCoupon` (public) + `resolveCouponForCharge` (private) — used **only** for tier; drop `membership` field + ctor param |
| `internal/order/api.go` — `ValidateCoupon(... userID)` signature + tier doc | Revert to no-`userID` signature |
| `cmd/core-svc/cart_enrich.go` — `cartCouponValidator.ValidateCoupon(... userID)` + call passing `c.UserID` | Drop the `userID` arg; **keep `c.UserID`** (the cart's own owner field, used elsewhere) |
| `migrations/ecom/0106_coupon_min_tier.*` | Leave shipped files; reverse forward in 0107 |
| account "your benefits" + cart `tier_locked` surfacing | see surfacing rows below |
| `membership.*` i18n + `account.tier_*` i18n | remove (8 keys × 4 locales) |
| `ELITE15` seed (inside 0106) | DELETE in 0107 |

### AC-05 — tier foundation
| Ref | Disposition |
|---|---|
| `internal/order/membership.go` (`MembershipService`, `Membership`, `MembershipTierDef`, `MembershipRepository`, `ErrNoMembershipTiers`, `MembershipWindowDays`) | Delete file |
| `internal/order/membership_repository.go` (`pgxMembershipRepository`, `NewMembershipRepository`) | Delete file |
| `cmd/core-svc/membership_handlers.go` (`handleGetMyMembership`) | Delete file |
| `cmd/core-svc/main.go` — `membershipSvc` build + `NewServiceFull(... membershipSvc)` arg + `GET /me/membership` route | Remove all three |
| `api/openapi.yaml` — `/me/membership` op + `Membership` schema | Remove → **regen Go+Dart** (`make api-gen`) |
| generated: `internal/api/gen/{types,core}/*.gen.go`, `mobile/packages/mopro_api/lib/src/model/membership.{dart,g.dart}`, `.../api/me_api.dart` (getMyMembership), `.../deserialize.dart`, `.../mopro_api.dart` (export) | Regenerated, not hand-edited |
| `migrations/ecom/0094_membership_tiers.*` (+ `deploy/postgres-ecom/init/40-ref-schema.sql`, `50-ref-seed.sql` lockstep) | Leave shipped migration; drop table in 0107; **remove from init** (fresh-DB lockstep) |
| mobile `account/widgets/membership_tier_card.dart`, `account/providers/membership_provider.dart`, `account/account_screen.dart` (import + `MembershipTierCard()` sliver) | Delete card + provider; remove from account screen |
| cart `cart/widgets/order_summary_card.dart` — `couponMessage=='tier_locked'` branch | Remove branch; keep the generic coupon-message fallback |

### Tests
| Ref | Disposition |
|---|---|
| `internal/order/membership_test.go`, `internal/order/membership_coupon_test.go` | Delete (tier-only suites) |
| `internal/order/coupon_test.go` | Remove tier cases; keep non-tier coupon cases |
| `cmd/core-svc/contract_test.go` — `TestContract_GetMyMembership` + `stubMembershipSvc` | Delete that block |
| `cmd/core-svc/{handlers_test,cart_enrich_test}.go`, `internal/shipping/service_test.go` (`stubOrderSvc.ValidateCoupon`) | Update `ValidateCoupon` stubs to the no-`userID` signature |
| `mobile/test/features/account/membership_tier_card_test.dart`, `mobile/packages/mopro_api/test/membership_test.dart` | Delete |

### False positives (leave untouched)
- `internal/sizefinder/basic_estimate.go` — "membership" = set membership (band centres), not loyalty.
- `mobile/.../pdp_size_recommendation.dart`, `account/providers/fit_profile_provider.dart` — comments saying the size card "mirrors the membership-card pattern"; reword to drop the now-deleted reference (no code dep).
- `internal/e2e/dlq_e2e_test.go` — "membership" = Redis consumer-group/stream membership.

## Ledger purity (anti-goal #1)
No file under `internal/cashback/`, `internal/wallet/`, `internal/ledger/`,
`internal/treasury/`, `internal/sellerpayout/` is touched. The tier read-model never
read postgres-ledger (it aggregated `order_schema.orders` only). Asserted by: those
suites unchanged + green, and `git diff --stat` showing no fin-svc/ledger paths.

## Migration 0107 (drop-forward)
- **up:** `DELETE ELITE15` → `ALTER … DROP COLUMN min_tier_rank` → `DROP TABLE ref_schema.membership_tiers`.
- **down (additive):** recreate `membership_tiers` + seed (mirror 0094), re-add
  `min_tier_rank DEFAULT 1`, re-insert `ELITE15` (mirror 0106).
- Round-trip up/down/up on a throwaway PG before claiming done.
