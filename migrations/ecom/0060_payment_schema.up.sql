-- 0060_payment_schema.up.sql
-- Links payments to checkout sessions for multi-seller checkout.
-- checkout_session_id is nullable: NULL = legacy single-order payment (order.Checkout).

ALTER TABLE order_schema.payments
    ADD COLUMN IF NOT EXISTS checkout_session_id
        TEXT REFERENCES order_schema.checkout_sessions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS payments_checkout_session_idx
    ON order_schema.payments (checkout_session_id)
    WHERE checkout_session_id IS NOT NULL;
