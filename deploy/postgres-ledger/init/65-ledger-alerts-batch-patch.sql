-- 65-ledger-alerts-batch-patch.sql — add batch_id and alert_type to wallet_schema.ledger_alerts.
--
-- ledger_alerts was created in 40-wallet-schema.sql for ledger reconciliation alerts.
-- Phase 2.3 extends it for two payout-engine use cases:
--   1. fraud_hold escalation: batch in-flight when ecom.seller.fraud_hold_set.v1 arrives.
--   2. ambiguous transfer:    PSP replay returns a different transfer_id than stored.
--
-- batch_id links the alert to the affected payout_batches row.
-- alert_type distinguishes payout alerts from generic ledger delta alerts.

ALTER TABLE wallet_schema.ledger_alerts
    ADD COLUMN IF NOT EXISTS batch_id   BIGINT,
    ADD COLUMN IF NOT EXISTS alert_type TEXT;

CREATE INDEX IF NOT EXISTS ledger_alerts_batch_idx
    ON wallet_schema.ledger_alerts(batch_id)
    WHERE batch_id IS NOT NULL AND acknowledged_at IS NULL;
