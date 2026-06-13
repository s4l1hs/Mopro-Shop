-- 0106_coupon_min_tier.up.sql
-- Membership benefits (Wave 2): tier-exclusive coupons. A coupon may require a
-- minimum membership tier RANK; only members at/above it may apply it. This is an
-- ELIGIBILITY gate only — it never changes the discount amount, so the proven
-- seller-funded coupon path (CT-03, migration 0092) is reused unchanged:
-- display==charge by construction, no new ledger account, no §12 (see
-- docs/internal/membership-benefits.md).
--
-- min_tier_rank references ref_schema.membership_tiers.rank (a stable ordinal;
-- 1 = classic/base = everyone). It is a SOFT ordinal — NOT a cross-schema FK
-- (§5: order_schema must not depend on ref_schema via FK). The order module
-- resolves a user's rank in-module (order.MembershipService over order_schema +
-- the ref_schema shared-read exception) and compares.
--
-- DEFAULT 1 makes this fully backward-compatible: every existing coupon keeps
-- min_tier_rank=1, i.e. available to all tiers — identical to pre-0106 behaviour.
ALTER TABLE order_schema.coupons
  ADD COLUMN IF NOT EXISTS min_tier_rank SMALLINT NOT NULL DEFAULT 1
      CHECK (min_tier_rank >= 1);

-- Dev/test seed: a tier-exclusive coupon for the top tier (rank 3 = elite). Lets
-- the cart/checkout flow exercise the tier_locked path. Creation/admin is out of
-- scope; harmless in prod (a demo code). Reuses the 0092 unique key.
INSERT INTO order_schema.coupons (code, kind, percent_off, min_basket_minor, market, min_tier_rank, expires_at)
VALUES ('ELITE15', 'percent', 15, 0, 'TR', 3, now() + interval '10 years')
ON CONFLICT (upper(code), market) DO NOTHING;
