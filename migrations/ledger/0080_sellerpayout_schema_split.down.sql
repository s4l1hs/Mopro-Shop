-- 0080_sellerpayout_schema_split.down.sql
-- Reverse 0080: move the three sellerpayout-owned tables (and the immutable
-- trigger function) back into commission_schema and drop sellerpayout_schema.
-- Guarded so it is safe regardless of current table location.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc p
                 JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'sellerpayout_schema'
                 AND p.proname = 'enforce_payout_immutable') THEN
        ALTER FUNCTION sellerpayout_schema.enforce_payout_immutable() SET SCHEMA commission_schema;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_tables
               WHERE schemaname = 'sellerpayout_schema' AND tablename = 'seller_payouts') THEN
        ALTER TABLE sellerpayout_schema.seller_payouts SET SCHEMA commission_schema;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_tables
               WHERE schemaname = 'sellerpayout_schema' AND tablename = 'payout_batches') THEN
        ALTER TABLE sellerpayout_schema.payout_batches SET SCHEMA commission_schema;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_tables
               WHERE schemaname = 'sellerpayout_schema' AND tablename = 'seller_psp_accounts') THEN
        ALTER TABLE sellerpayout_schema.seller_psp_accounts SET SCHEMA commission_schema;
    END IF;
END $$;

-- reconcile_user's pre-split grant lived on commission_schema.seller_payouts;
-- re-assert it now the table is back (the original grant persisted with the
-- table object, this is belt-and-suspenders for a clean rollback).
GRANT SELECT ON commission_schema.seller_payouts TO reconcile_user;

DROP SCHEMA IF EXISTS sellerpayout_schema;
