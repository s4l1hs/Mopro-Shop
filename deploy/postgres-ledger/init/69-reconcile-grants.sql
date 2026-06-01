-- 69-reconcile-grants.sql — reconcile_user role with read-only cross-schema access.
-- EXCEPTION to CLAUDE.md §5: reconcile_user may query wallet_schema + cashback_schema
-- + commission_schema in a single SQL statement for invariant verification only.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'reconcile_user') THEN
    CREATE ROLE reconcile_user WITH LOGIN PASSWORD 'reconcile_password';
  END IF;
END
$$;

-- wallet_schema: SELECT on data tables; INSERT on alerts + outbox; UPDATE on system_state
GRANT USAGE ON SCHEMA wallet_schema TO reconcile_user;
GRANT SELECT ON wallet_schema.transactions      TO reconcile_user;
GRANT SELECT ON wallet_schema.ledger_entries    TO reconcile_user;
GRANT SELECT ON wallet_schema.accounts          TO reconcile_user;
GRANT SELECT ON wallet_schema.ledger_alerts     TO reconcile_user;
GRANT SELECT, UPDATE ON wallet_schema.system_state TO reconcile_user;
GRANT INSERT ON wallet_schema.ledger_alerts     TO reconcile_user;
GRANT INSERT ON wallet_schema.outbox            TO reconcile_user;

-- Sequence grants needed for BIGSERIAL INSERT
GRANT USAGE, SELECT ON SEQUENCE wallet_schema.ledger_alerts_id_seq TO reconcile_user;
GRANT USAGE, SELECT ON SEQUENCE wallet_schema.outbox_id_seq TO reconcile_user;

-- cashback_schema: SELECT only (for Check 2 backward check)
GRANT USAGE ON SCHEMA cashback_schema TO reconcile_user;
GRANT SELECT ON cashback_schema.payments        TO reconcile_user;
GRANT SELECT ON cashback_schema.plans           TO reconcile_user;

-- commission_schema: USAGE only (kept for future Check 4/5 in Phase 5).
GRANT USAGE ON SCHEMA commission_schema TO reconcile_user;

-- sellerpayout_schema: SELECT on seller_payouts (relocated here by the schema
-- split; reconcile reads it for payout invariant checks).
GRANT USAGE ON SCHEMA sellerpayout_schema TO reconcile_user;
GRANT SELECT ON sellerpayout_schema.seller_payouts TO reconcile_user;
