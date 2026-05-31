-- 0070_returns.up.sql — consumer-side return requests for delivered orders.
--
-- Wires the OpenAPI-declared CreateReturn/ListReturns surface (api/openapi.yaml)
-- that the PR #21 audit found spec'd-but-unimplemented. Three tables:
--   returns               — one row per return request (header: reason, status, refund)
--   return_items          — the order items + quantities in a return
--   return_status_history — append-only audit of status transitions
--
-- Storage-layer idempotency (same discipline as cashback payments_made and
-- reviews helpful_count): the UNIQUE (order_id, order_item_id) on return_items
-- means an order item can be in at most one return — concurrent submissions for
-- the same item collide at the database (23505), so N racing requests converge
-- to one row.

CREATE TABLE IF NOT EXISTS order_schema.returns (
    id                  BIGSERIAL   PRIMARY KEY,
    order_id            BIGINT      NOT NULL,
    user_id             BIGINT      NOT NULL,
    status              TEXT        NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','approved','rejected','refunded')),
    reason              TEXT        NOT NULL
                        CHECK (reason IN ('wrong_product','not_as_described','damaged',
                                          'size_issue','changed_mind','other')),
    description         TEXT        NOT NULL DEFAULT '',
    refund_amount_minor BIGINT      NOT NULL DEFAULT 0,
    refund_currency     TEXT        NOT NULL DEFAULT '',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS returns_user_created_idx
    ON order_schema.returns (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS returns_order_idx
    ON order_schema.returns (order_id);

CREATE TABLE IF NOT EXISTS order_schema.return_items (
    id            BIGSERIAL PRIMARY KEY,
    return_id     BIGINT    NOT NULL REFERENCES order_schema.returns(id) ON DELETE CASCADE,
    order_id      BIGINT    NOT NULL,
    order_item_id BIGINT    NOT NULL,
    quantity      INT       NOT NULL CHECK (quantity >= 1),
    -- storage-layer idempotency: an order item belongs to at most one return.
    CONSTRAINT return_items_order_item_uniq UNIQUE (order_id, order_item_id)
);

CREATE INDEX IF NOT EXISTS return_items_return_idx
    ON order_schema.return_items (return_id);

CREATE TABLE IF NOT EXISTS order_schema.return_status_history (
    id         BIGSERIAL   PRIMARY KEY,
    return_id  BIGINT      NOT NULL REFERENCES order_schema.returns(id) ON DELETE CASCADE,
    status     TEXT        NOT NULL,
    note       TEXT        NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS return_status_history_return_idx
    ON order_schema.return_status_history (return_id, created_at);
