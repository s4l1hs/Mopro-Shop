-- 0077_order_capture_postings.up.sql
-- Adds two new platform accounts and the capture_postings audit table for
-- the orderledger consumer (ecom.order.paid.v1 → balanced 4-or-5-line posting).

-- 1. New platform accounts seeded idempotently.
--    asset:psp_receivable  — DR when PSP captures payment (funds in transit to escrow).
--    liability:shipping_payable — CR for the buyer-paid shipping component (if any).
INSERT INTO wallet_schema.accounts (type, owner_type, owner_id, currency, status) VALUES
  ('asset:psp_receivable',        'platform', NULL, 'TRY', 'active'),
  ('liability:shipping_payable',  'platform', NULL, 'TRY', 'active')
ON CONFLICT DO NOTHING;

-- 2. commission_schema.capture_postings — one row per paid order.
--    Idempotency is enforced by UNIQUE(order_id).
--    The wallet.PostInTx idempotency key ('order:capture:order_<id>') provides a
--    second independent guard at the transactions.idempotency_key UNIQUE constraint.
CREATE TABLE IF NOT EXISTS commission_schema.capture_postings (
    id               BIGSERIAL     PRIMARY KEY,
    order_id         BIGINT        NOT NULL,
    transaction_id   BIGINT        NOT NULL REFERENCES wallet_schema.transactions(id),
    idempotency_key  TEXT          NOT NULL,
    gross_minor      BIGINT        NOT NULL CHECK (gross_minor > 0),
    seller_net_minor BIGINT        NOT NULL CHECK (seller_net_minor > 0),
    commission_minor BIGINT        NOT NULL CHECK (commission_minor >= 0),
    kdv_minor        BIGINT        NOT NULL CHECK (kdv_minor >= 0),
    shipping_minor   BIGINT        NOT NULL CHECK (shipping_minor >= 0),
    currency         TEXT          NOT NULL,
    market           TEXT          NOT NULL,
    status           TEXT          NOT NULL DEFAULT 'posted',
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT capture_postings_order_id_uq     UNIQUE (order_id),
    CONSTRAINT capture_postings_idem_key_uq     UNIQUE (idempotency_key)
);

CREATE INDEX IF NOT EXISTS capture_postings_created_at_idx
    ON commission_schema.capture_postings (created_at DESC);

-- 3. No-delete / no-update rules (append-only, matching ledger_entries pattern).
CREATE RULE no_update_capture_postings AS
    ON UPDATE TO commission_schema.capture_postings DO INSTEAD NOTHING;

CREATE RULE no_delete_capture_postings AS
    ON DELETE TO commission_schema.capture_postings DO INSTEAD NOTHING;

-- 4. Grant DML to wallet_user so the orderledger service (which shares the
--    fin-svc pool connected as wallet_user) can write capture_postings rows.
GRANT SELECT, INSERT ON commission_schema.capture_postings TO wallet_user;
GRANT USAGE, SELECT ON SEQUENCE commission_schema.capture_postings_id_seq TO wallet_user;
