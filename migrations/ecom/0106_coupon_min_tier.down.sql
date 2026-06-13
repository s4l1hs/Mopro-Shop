-- 0106_coupon_min_tier.down.sql — reverse the tier-exclusive coupon column + seed.
DELETE FROM order_schema.coupons WHERE upper(code) = 'ELITE15' AND market = 'TR';
ALTER TABLE order_schema.coupons DROP COLUMN IF EXISTS min_tier_rank;
