-- 40-ref-schema.sql — create ref_schema tables.
-- All tables are read-only at runtime; populated by 50-ref-seed.sql and /migrations/ecom/seed/.

CREATE TABLE IF NOT EXISTS ref_schema.currencies (
  code             TEXT        NOT NULL,
  kind             TEXT        NOT NULL CHECK (kind IN ('fiat', 'coin')),
  minor_unit_scale INT         NOT NULL DEFAULT 2,
  symbol           TEXT        NOT NULL,
  name_en          TEXT        NOT NULL,
  active           BOOL        NOT NULL DEFAULT FALSE,
  PRIMARY KEY (code)
);

CREATE TABLE IF NOT EXISTS ref_schema.countries (
  code             TEXT        NOT NULL,
  name_en          TEXT        NOT NULL,
  default_currency TEXT        NOT NULL REFERENCES ref_schema.currencies(code),
  default_locale   TEXT        NOT NULL,
  default_timezone TEXT        NOT NULL,
  PRIMARY KEY (code)
);

CREATE TABLE IF NOT EXISTS ref_schema.locales (
  tag              TEXT        NOT NULL,
  name_en          TEXT        NOT NULL,
  active           BOOL        NOT NULL DEFAULT FALSE,
  PRIMARY KEY (tag)
);

CREATE TABLE IF NOT EXISTS ref_schema.categories (
  id               BIGINT      NOT NULL,
  slug             TEXT        NOT NULL,
  name_tr          TEXT        NOT NULL,
  name_en          TEXT        NOT NULL,
  parent_id        BIGINT      REFERENCES ref_schema.categories(id),
  active           BOOL        NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id),
  UNIQUE (slug)
);

-- Backs the PLP-12 subtree-rollup recursive CTE (parent_id → children). Mirrors
-- migration 0088 so fresh provisions match the migrated path.
CREATE INDEX IF NOT EXISTS categories_parent_id_idx
  ON ref_schema.categories (parent_id);

CREATE TABLE IF NOT EXISTS ref_schema.commission_rules (
  id                   BIGSERIAL   NOT NULL,
  market               TEXT        NOT NULL,
  category_id          BIGINT      NOT NULL REFERENCES ref_schema.categories(id),
  commission_pct_bps   INT         NOT NULL CHECK (commission_pct_bps BETWEEN 0 AND 10000),
  kdv_pct_bps          INT         NOT NULL CHECK (kdv_pct_bps BETWEEN 0 AND 10000),
  effective_from       TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to         TIMESTAMPTZ,
  active               BOOL        NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id),
  UNIQUE (market, category_id, effective_from)
);

CREATE TABLE IF NOT EXISTS ref_schema.business_calendars (
  market           TEXT        NOT NULL,
  date             DATE        NOT NULL,
  reason           TEXT        NOT NULL,
  PRIMARY KEY (market, date)
);

-- AC-05: membership-tier ladder (reference data; lockstep with migration 0094).
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
