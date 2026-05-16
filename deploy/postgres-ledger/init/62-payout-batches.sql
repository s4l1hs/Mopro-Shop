-- 62-payout-batches.sql — commission_schema.payout_batches aggregation table.
--
-- One batch per (seller_id, currency, payout_date); groups all seller_payouts
-- for that seller on that date into a single Sipay transfer.
-- Idempotency key: 'payout:seller_{id}:date_{YYYYMMDD}:ccy_{CCY}'.
--
-- 3-phase sandwich:
--   Tx1  → status='processing'   (optimistic lock; crash here → batch stays 'pending')
--   PSP  → psp_transfer_id set via non-tx UPDATE
--   Tx2  → status='paid', ledger_transaction_id set atomically
--
-- reconcile_processing scans 'processing' batches older than 10 min and retries.

CREATE TABLE commission_schema.payout_batches (
  id                    BIGSERIAL PRIMARY KEY,
  seller_id             BIGINT NOT NULL,
  currency              TEXT NOT NULL,
  payout_date           DATE NOT NULL,
  total_amount_minor    BIGINT NOT NULL CHECK (total_amount_minor > 0),
  psp_transfer_id       TEXT,
  status                TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','processing','paid','failed','ambiguous','cancelled')),
  ledger_transaction_id BIGINT,
  paid_at               TIMESTAMPTZ,
  idempotency_key       TEXT NOT NULL UNIQUE,
  attempt_count         INTEGER NOT NULL DEFAULT 0,
  last_attempt_at       TIMESTAMPTZ,
  last_error            TEXT,
  market                TEXT NOT NULL DEFAULT 'TR',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX payout_batches_pending_idx
    ON commission_schema.payout_batches(payout_date, status)
    WHERE status IN ('pending','processing');

CREATE INDEX payout_batches_processing_recovery_idx
    ON commission_schema.payout_batches(status, last_attempt_at)
    WHERE status = 'processing';

CREATE INDEX payout_batches_seller_idx
    ON commission_schema.payout_batches(seller_id, payout_date DESC);
