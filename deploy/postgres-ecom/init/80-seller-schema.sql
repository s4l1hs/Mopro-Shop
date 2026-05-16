-- 80-seller-schema.sql — minimal seller_schema.sellers table for phase 2.3 test setup.
-- The full seller module (profile, bank accounts, IBAN, KYC) is built in Phase 3.
-- fin-svc never reads postgres-ecom; this table is used only for core-svc and integration tests.

CREATE TABLE IF NOT EXISTS seller_schema.sellers (
  id             BIGSERIAL PRIMARY KEY,
  name           TEXT NOT NULL,
  psp_member_id  TEXT,                   -- Sipay marketplace member ID; populated after PSP onboarding
  market         TEXT NOT NULL DEFAULT 'TR',
  status         TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','suspended','pending')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sellers_status_idx ON seller_schema.sellers(status);
