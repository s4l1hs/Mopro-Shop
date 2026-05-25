-- 0062_payment_schema_v2.down.sql
DROP INDEX IF EXISTS order_schema.payments_status_expires_idx;

ALTER TABLE order_schema.payments
    DROP COLUMN IF EXISTS sipay_3ds_url,
    DROP COLUMN IF EXISTS expires_at;
