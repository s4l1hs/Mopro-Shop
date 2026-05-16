-- 68-reconcile-alerts-patch.sql — add context JSONB to wallet_schema.ledger_alerts.
-- Phase 2.4: stores {check_name, currency_or_period, expected, observed, drift_minor}.

ALTER TABLE wallet_schema.ledger_alerts
    ADD COLUMN IF NOT EXISTS context JSONB;
