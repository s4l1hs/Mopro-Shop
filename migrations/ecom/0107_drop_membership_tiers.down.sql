-- 0107_drop_membership_tiers.down.sql
-- Rollback: recreate the tier scaffolding additively (mirrors 0094 + 0106) so a
-- prior image that still reads tiers can run again. Idempotent.

-- AC-05 tier ladder (mirror of 0094).
CREATE TABLE IF NOT EXISTS ref_schema.membership_tiers (
  code            TEXT   NOT NULL,
  market          TEXT   NOT NULL,
  rank            INT    NOT NULL CHECK (rank >= 1),
  currency        TEXT   NOT NULL,
  min_spend_minor BIGINT NOT NULL DEFAULT 0 CHECK (min_spend_minor >= 0),
  min_orders      INT    NOT NULL DEFAULT 0 CHECK (min_orders >= 0),
  active          BOOL   NOT NULL DEFAULT TRUE,
  PRIMARY KEY (market, code),
  UNIQUE (market, rank)
);

INSERT INTO ref_schema.membership_tiers
  (code, market, rank, currency, min_spend_minor, min_orders, active)
VALUES
  ('classic', 'TR', 1, 'TRY',       0,  0, TRUE),
  ('gold',    'TR', 2, 'TRY',  250000,  5, TRUE),
  ('elite',   'TR', 3, 'TRY', 1000000, 15, TRUE)
ON CONFLICT (market, code) DO NOTHING;

-- #222 coupon gate (mirror of 0106): backward-compatible DEFAULT 1.
ALTER TABLE order_schema.coupons
  ADD COLUMN IF NOT EXISTS min_tier_rank SMALLINT NOT NULL DEFAULT 1
      CHECK (min_tier_rank >= 1);

INSERT INTO order_schema.coupons (code, kind, percent_off, min_basket_minor, market, min_tier_rank, expires_at)
VALUES ('ELITE15', 'percent', 15, 0, 'TR', 3, now() + interval '10 years')
ON CONFLICT (upper(code), market) DO NOTHING;
