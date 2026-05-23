-- 0059_orders_v8.down.sql
ALTER TABLE order_schema.orders
    DROP COLUMN IF EXISTS checkout_session_id,
    DROP COLUMN IF EXISTS seller_id;
