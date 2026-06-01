-- 60-seller-payout-schema.sql — seller payout records (sellerpayout_schema).
-- Source: DATA_DICTIONARY.md § 9.
--
-- seller_payouts lives in sellerpayout_schema, owned by the sellerpayout module
-- (relocated out of commission_schema by chore/sellerpayout-schema-split; see
-- DATA_DICTIONARY.md § 2.2 / § 9). sellerpayout_user has DML on
-- sellerpayout_schema (see 30-grants.sql).
--
-- unlock_at = delivered_at + 3 business days (computed via pkg/timex.AddBusinessDays).
-- amount_minor and unlock_at are IMMUTABLE once set (enforced by 61-seller-payout-immutable-trigger.sql).
-- Corrections happen ONLY via reversal transactions (new reversed row), never UPDATE.

CREATE TABLE sellerpayout_schema.seller_payouts (
  id                    BIGSERIAL PRIMARY KEY,
  order_id              BIGINT NOT NULL,                                    -- denormalized; no FK across cluster
  seller_id             BIGINT NOT NULL,
  amount_minor          BIGINT NOT NULL CHECK (amount_minor > 0),           -- snapshotted seller_net_minor sum
  currency              TEXT NOT NULL DEFAULT 'TRY',
  delivered_at          TIMESTAMPTZ NOT NULL,                               -- when kargo confirmed delivered
  unlock_at             DATE NOT NULL,                                      -- = delivered_at + 3 business days
  paid_at               TIMESTAMPTZ,
  psp_transfer_id       TEXT,                                               -- PSP provider's transfer reference
  status                TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled','processing','paid','failed','cancelled','reversed')),
  market                TEXT NOT NULL DEFAULT 'TR',
  ledger_transaction_id BIGINT,                                             -- set when ledger move completes
  idempotency_key       TEXT NOT NULL UNIQUE,                               -- 'payout:order_<id>:seller_<id>'
  attempt_count         INTEGER NOT NULL DEFAULT 0,
  last_attempt_at       TIMESTAMPTZ,
  last_error            TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX seller_payouts_due_idx
    ON sellerpayout_schema.seller_payouts(unlock_at, status) WHERE status = 'scheduled';
CREATE INDEX seller_payouts_seller_idx
    ON sellerpayout_schema.seller_payouts(seller_id, created_at DESC);
CREATE INDEX seller_payouts_order_idx
    ON sellerpayout_schema.seller_payouts(order_id);
