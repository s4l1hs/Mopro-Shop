-- 0059_orders_v8.up.sql
-- Adds seller_id and checkout_session_id to orders for multi-seller checkout support.
-- Both columns are nullable: NULL = legacy single-order flow (order.Checkout).

ALTER TABLE order_schema.orders
    ADD COLUMN IF NOT EXISTS seller_id
        BIGINT,
    ADD COLUMN IF NOT EXISTS checkout_session_id
        TEXT REFERENCES order_schema.checkout_sessions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS orders_checkout_session_idx
    ON order_schema.orders (checkout_session_id)
    WHERE checkout_session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS orders_seller_idx
    ON order_schema.orders (seller_id, created_at DESC)
    WHERE seller_id IS NOT NULL;
