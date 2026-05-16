-- 64-seller-psp-accounts.sql — commission_schema.seller_psp_accounts.
--
-- fin-svc cannot reach postgres-ecom (network isolation: CLAUDE.md § 2.1).
-- This table mirrors the seller's PSP registration on the ledger side.
-- Populated by consuming ecom.seller.psp_onboarded.v1 from Redis Streams.
--
-- One row per seller; psp_member_id is the Sipay marketplace member ID used
-- in every seller payout transfer call.

CREATE TABLE commission_schema.seller_psp_accounts (
  id             BIGSERIAL PRIMARY KEY,
  seller_id      BIGINT NOT NULL UNIQUE,
  psp_member_id  TEXT NOT NULL,
  market         TEXT NOT NULL DEFAULT 'TR',
  status         TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','suspended')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX seller_psp_accounts_status_idx
    ON commission_schema.seller_psp_accounts(status)
    WHERE status = 'active';
