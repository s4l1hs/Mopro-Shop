-- 70-payments.sql — order_schema.payments
-- PCI-SAFE: stores no card data. Card entry is hosted exclusively by Sipay (SAQ-A scope).
-- Each row tracks one payment initiation attempt for an order.
-- A single order_id may have multiple rows if the buyer retried after failure.

CREATE TABLE IF NOT EXISTS order_schema.payments (
    id                  BIGSERIAL PRIMARY KEY,

    order_id            BIGINT      NOT NULL REFERENCES order_schema.orders(id),
    idempotency_key     TEXT        NOT NULL,   -- caller-supplied; = Sipay invoice_id
    provider            TEXT        NOT NULL,   -- 'sipay' | 'craftgate' | 'iyzico'
    provider_ref        TEXT        NOT NULL DEFAULT '',  -- PSP's reference (= idempotency_key for Sipay)
    provider_order_no   TEXT        NOT NULL DEFAULT '',  -- PSP's internal order number

    status              TEXT        NOT NULL DEFAULT 'pending',  -- pending|captured|failed|refunded|unknown
    amount_minor        BIGINT      NOT NULL,
    currency            TEXT        NOT NULL,

    captured_at         TIMESTAMPTZ,
    failed_at           TIMESTAMPTZ,
    failure_reason      TEXT        NOT NULL DEFAULT '',
    refunded_at         TIMESTAMPTZ,
    refund_ref          TEXT        NOT NULL DEFAULT '',
    refund_amount_minor BIGINT      NOT NULL DEFAULT 0,

    -- PCI-SAFE: raw_response stores only PSP metadata (status codes, references).
    -- Card numbers, CVVs, and cardholder data NEVER appear here.
    raw_response        JSONB,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT payments_idempotency_key_uq UNIQUE (idempotency_key)
);

-- Fast lookup by PSP reference for webhook dedup and status polling.
CREATE INDEX IF NOT EXISTS payments_provider_ref_idx
    ON order_schema.payments (provider_ref);

-- Fast lookup by order to retrieve payment history.
CREATE INDEX IF NOT EXISTS payments_order_id_idx
    ON order_schema.payments (order_id);
