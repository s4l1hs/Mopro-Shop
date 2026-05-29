-- 0078_drop_stale_ref_rate_check.down.sql
-- Reverse: re-add the CHECK that 0078 dropped. Note: this will fail if any
-- v8 plans with reference_interest_rate_bps = 0 are present (which is the
-- whole reason the up migration exists).

ALTER TABLE cashback_schema.plans
    ADD CONSTRAINT plans_reference_interest_rate_bps_check
    CHECK (reference_interest_rate_bps BETWEEN 1 AND 20000);
