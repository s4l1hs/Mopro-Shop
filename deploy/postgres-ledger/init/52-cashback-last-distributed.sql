-- 52-cashback-last-distributed.sql
-- Adds last_distributed_period column to cashback_schema.plans for the monthly cron
-- cursor-pagination pattern. The cron UPDATE sets this after each successful payment,
-- and the batch SELECT uses it to skip plans already paid for the current period.
-- Also adds the composite partial index used by the cron query.

ALTER TABLE cashback_schema.plans
    ADD COLUMN IF NOT EXISTS last_distributed_period INTEGER
    CHECK (last_distributed_period IS NULL OR last_distributed_period BETWEEN 202600 AND 209912);

CREATE INDEX IF NOT EXISTS cashback_plans_cron_idx
    ON cashback_schema.plans (id, start_date, last_distributed_period)
    WHERE status = 'active';
