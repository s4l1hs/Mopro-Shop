-- 0062_payment_schema_v2.up.sql
-- Adds sipay_3ds_url and expires_at to order_schema.payments.
-- expires_at enables the background reconciler to find sessions stuck
-- in 'pending' state after Sipay's 3DS window (default 30 min).

ALTER TABLE order_schema.payments
    ADD COLUMN IF NOT EXISTS sipay_3ds_url TEXT,
    ADD COLUMN IF NOT EXISTS expires_at    TIMESTAMPTZ;

-- Backfill: assume all existing pending rows expire 30 minutes after creation.
UPDATE order_schema.payments
   SET expires_at = created_at + INTERVAL '30 minutes'
 WHERE expires_at IS NULL
   AND status = 'pending';

-- Index for the reconciler query:
-- SELECT ... WHERE status='pending' AND expires_at < NOW() - INTERVAL '2 minutes'
CREATE INDEX IF NOT EXISTS payments_status_expires_idx
    ON order_schema.payments (status, expires_at)
    WHERE status = 'pending';
