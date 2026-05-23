-- 0060_payment_schema.down.sql
ALTER TABLE order_schema.payments
    DROP COLUMN IF EXISTS checkout_session_id;
