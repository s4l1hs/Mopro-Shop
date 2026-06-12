-- 0094_membership_tiers.up.sql
-- AC-05 phase 1: membership-tier reference data.
--
-- Tiers (classic/gold/elite at TR launch) are REFERENCE DATA, not code
-- constants — CLAUDE.md forbids hardcoded market/currency/threshold values, and
-- adding a market must be config + seed only. The tier itself is a pure derived
-- read-model (computed per-request from order_schema.orders by the order
-- module's MembershipService); this table only declares the ladder.
--
-- ref_schema is SELECT-able by every module (the explicit §5 shared-read
-- exception) and 30-grants.sql declares ALTER DEFAULT PRIVILEGES → GRANT SELECT
-- TO PUBLIC for new ref tables, so no per-role grant block is needed here.
-- Thresholds are AND-ed (both spend AND orders must be met) over a rolling
-- window whose length the API reports (365 days at launch).
--
-- The fresh-DB source (deploy/postgres-ecom/init/40-ref-schema.sql +
-- 50-ref-seed.sql) is updated in lockstep; this migration carries
-- already-provisioned databases across the same change. IDEMPOTENT.

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
