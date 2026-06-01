-- 63-seller-payouts-batch-id.sql — add batch_id FK to seller_payouts.
--
-- Links each individual payout row to its aggregation batch so the daily cron
-- can update all constituent payouts atomically as part of Tx1.
-- Also adds a recovery index for reconcile_processing.

ALTER TABLE sellerpayout_schema.seller_payouts
    ADD COLUMN IF NOT EXISTS batch_id BIGINT
        REFERENCES sellerpayout_schema.payout_batches(id);

CREATE INDEX IF NOT EXISTS seller_payouts_batch_idx
    ON sellerpayout_schema.seller_payouts(batch_id)
    WHERE batch_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS seller_payouts_processing_idx
    ON sellerpayout_schema.seller_payouts(status, last_attempt_at)
    WHERE status = 'processing';
