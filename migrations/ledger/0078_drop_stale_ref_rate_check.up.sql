-- 0078_drop_stale_ref_rate_check.up.sql
-- Hygiene fix: 0076_cashback_accelerated_v8 set
--     ALTER COLUMN reference_interest_rate_bps SET DEFAULT 0
-- but left the original CHECK (BETWEEN 1 AND 20000) from the initial schema
-- (deploy/postgres-ledger/init/50-cashback-schema.sql) in place. v8 INSERTs
-- that omit the column now write 0, which violates the surviving CHECK and
-- blocks every cashback integration/property test.
--
-- This drop unblocks integration tests so the cashback storage-layer
-- idempotency PR can be verified end-to-end. The column remains in v8 plans
-- as a legacy field (always 0 for v8 plans) — the constraint name is the
-- auto-generated one from the original CREATE TABLE.

ALTER TABLE cashback_schema.plans
    DROP CONSTRAINT IF EXISTS plans_reference_interest_rate_bps_check;
