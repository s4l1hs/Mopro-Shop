-- 0080_sellerpayout_schema_split.up.sql
-- Relocate the three sellerpayout-owned tables out of commission_schema into a
-- dedicated sellerpayout_schema, closing the PR #8 boundaries-guard exemption
-- (internal/sellerpayout reading commission_schema). The fresh-DB init scripts
-- (deploy/postgres-ledger/init/) are updated in lockstep; this migration carries
-- already-deployed databases across the same move.
--
-- IDEMPOTENT BY DESIGN: the test harness (make pg-ledger-test-up) applies the
-- init scripts AND every migration to a fresh DB. On such a DB the tables are
-- already created in sellerpayout_schema by the updated init, so each move is
-- guarded and becomes a no-op. On a real deployed DB (tables still in
-- commission_schema) the guards fire and perform the relocation.

CREATE SCHEMA IF NOT EXISTS sellerpayout_schema AUTHORIZATION sellerpayout_user;

-- Table-level grants persist with the table objects across SET SCHEMA, but the
-- new schema itself needs USAGE granted to every role that reaches its tables.
GRANT USAGE ON SCHEMA sellerpayout_schema TO sellerpayout_user;
GRANT USAGE ON SCHEMA sellerpayout_schema TO reconcile_user;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_tables
               WHERE schemaname = 'commission_schema' AND tablename = 'seller_payouts') THEN
        ALTER TABLE commission_schema.seller_payouts SET SCHEMA sellerpayout_schema;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_tables
               WHERE schemaname = 'commission_schema' AND tablename = 'payout_batches') THEN
        ALTER TABLE commission_schema.payout_batches SET SCHEMA sellerpayout_schema;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_tables
               WHERE schemaname = 'commission_schema' AND tablename = 'seller_psp_accounts') THEN
        ALTER TABLE commission_schema.seller_psp_accounts SET SCHEMA sellerpayout_schema;
    END IF;
    -- The immutable-trigger FUNCTION does not travel with the table on SET
    -- SCHEMA (only the trigger binding does), so relocate it explicitly.
    IF EXISTS (SELECT 1 FROM pg_proc p
                 JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'commission_schema'
                 AND p.proname = 'enforce_payout_immutable') THEN
        ALTER FUNCTION commission_schema.enforce_payout_immutable() SET SCHEMA sellerpayout_schema;
    END IF;
END $$;

-- Future tables/sequences created by sellerpayout_user in the new schema inherit
-- DML (mirrors the commission_schema defaults that previously covered these).
ALTER DEFAULT PRIVILEGES FOR ROLE sellerpayout_user IN SCHEMA sellerpayout_schema
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO sellerpayout_user;
ALTER DEFAULT PRIVILEGES FOR ROLE sellerpayout_user IN SCHEMA sellerpayout_schema
    GRANT USAGE, SELECT ON SEQUENCES TO sellerpayout_user;

-- reconcile_user keeps read-only access to seller_payouts (was on
-- commission_schema; the table grant persisted across the move, USAGE granted
-- above). Re-assert idempotently for already-migrated DBs.
GRANT SELECT ON sellerpayout_schema.seller_payouts TO reconcile_user;
