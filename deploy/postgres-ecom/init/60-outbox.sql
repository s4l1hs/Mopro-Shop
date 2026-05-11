-- 60-outbox.sql — order_schema.outbox table for ecom-side event publishing.
-- Mirror of wallet_schema.outbox in postgres-ledger (LEDGER_GUIDE.md § 5).
-- Owned by order_user. Cross-module DML granted in 30-grants.sql for
-- cart_user, payment_user, seller_user, identity_user, catalog_user.

CREATE TABLE order_schema.outbox (
    id              BIGSERIAL PRIMARY KEY,
    aggregate       TEXT NOT NULL,
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    trace_id        TEXT,
    span_id         TEXT,
    market          TEXT NOT NULL,
    currency        TEXT NOT NULL,
    published_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX outbox_unpublished_idx
    ON order_schema.outbox(created_at) WHERE published_at IS NULL;
