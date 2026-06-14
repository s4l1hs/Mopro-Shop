-- 0107_drop_membership_tiers.up.sql
-- Membership tiering is cancelled (ADR-0006). Cashback/coin is the sole loyalty
-- mechanism; all tier scaffolding is removed. This is the CONTRACT phase of an
-- expand/contract: it is safe ONLY once the tier-reading code is gone from the
-- running image — i.e. the new core-svc (which no longer SELECTs min_tier_rank in
-- GetCouponByCode, no longer serves /me/membership, and no longer reads
-- ref_schema.membership_tiers) MUST be live before/with this migration. See
-- RUNBOOK §5 migration checkpoint. The cashback/coin ledger is NOT touched.
--
-- Reverses #222 (0106: coupons.min_tier_rank + the ELITE15 demo coupon) and
-- AC-05 (0094: ref_schema.membership_tiers). 0094/0106 are left in history,
-- never rewritten.

-- Delete the rank-3 demo coupon BEFORE dropping the gate, so removing the gate
-- never silently widens it to everyone. ELITE15 was a dev/test-only demo code.
DELETE FROM order_schema.coupons WHERE upper(code) = 'ELITE15' AND market = 'TR';

-- Drop the tier-eligibility gate; coupons resolve for everyone (pre-#222).
ALTER TABLE order_schema.coupons DROP COLUMN IF EXISTS min_tier_rank;

-- Drop the AC-05 tier ladder reference table.
DROP TABLE IF EXISTS ref_schema.membership_tiers;
