-- 0076_cashback_accelerated_v8.up.sql
-- Transition cashback_schema.plans from v6 perpetual model to v8 accelerated
-- amortization model. Production plans table is confirmed empty — no backfill needed.

-- 1. New v8 columns.
--    monthly_amount_minor already exists from the initial plans table creation.
--    reference_interest_rate_bps still exists; give it DEFAULT 0 so v8 INSERTs can omit it.

ALTER TABLE cashback_schema.plans
    ADD COLUMN price_minor               BIGINT   NOT NULL,
    ADD COLUMN commission_bps            INTEGER  NOT NULL,
    ADD COLUMN total_months              INTEGER  NOT NULL,
    ADD COLUMN monthly_amount_last_minor BIGINT   NOT NULL,
    ADD COLUMN payments_made             INTEGER  NOT NULL DEFAULT 0;

ALTER TABLE cashback_schema.plans
    ALTER COLUMN reference_interest_rate_bps SET DEFAULT 0;

-- 2. Invariant constraints (enforced at DB level as a safety net; the Go layer
--    also validates via ComputePlanTerms before inserting).

ALTER TABLE cashback_schema.plans
    ADD CONSTRAINT plans_total_months_positive  CHECK (total_months >= 1),
    ADD CONSTRAINT plans_monthly_positive       CHECK (monthly_amount_minor >= 1),
    ADD CONSTRAINT plans_last_gte_monthly       CHECK (monthly_amount_last_minor >= monthly_amount_minor),
    ADD CONSTRAINT plans_payments_within_total  CHECK (payments_made >= 0 AND payments_made <= total_months),
    ADD CONSTRAINT plans_principal_exact        CHECK (
        (total_months - 1) * monthly_amount_minor + monthly_amount_last_minor = price_minor
    );

-- 3. Unique index on order_id — idempotency for InsertPlanIfAbsent.
--    IF NOT EXISTS is safe if a prior migration already added it.
CREATE UNIQUE INDEX IF NOT EXISTS plans_order_id_unique
    ON cashback_schema.plans (order_id);

-- 4. Replace the immutability trigger to cover all 9 v8 frozen columns.
--    Mutable columns: status, payments_made, updated_at, last_distributed_period.
CREATE OR REPLACE FUNCTION cashback_schema.plans_immutable_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (
        OLD.order_id                    IS DISTINCT FROM NEW.order_id OR
        OLD.user_id                     IS DISTINCT FROM NEW.user_id OR
        OLD.price_minor                 IS DISTINCT FROM NEW.price_minor OR
        OLD.commission_bps              IS DISTINCT FROM NEW.commission_bps OR
        OLD.currency                    IS DISTINCT FROM NEW.currency OR
        OLD.total_months                IS DISTINCT FROM NEW.total_months OR
        OLD.monthly_amount_minor        IS DISTINCT FROM NEW.monthly_amount_minor OR
        OLD.monthly_amount_last_minor   IS DISTINCT FROM NEW.monthly_amount_last_minor OR
        OLD.start_date                  IS DISTINCT FROM NEW.start_date OR
        OLD.delivered_at                IS DISTINCT FROM NEW.delivered_at OR
        (OLD.product_id        IS NOT NULL AND OLD.product_id        IS DISTINCT FROM NEW.product_id) OR
        (OLD.product_title     IS NOT NULL AND OLD.product_title     IS DISTINCT FROM NEW.product_title) OR
        (OLD.product_image_url IS NOT NULL AND OLD.product_image_url IS DISTINCT FROM NEW.product_image_url)
    ) THEN
        RAISE EXCEPTION 'cashback_schema.plans: immutable column update attempted';
    END IF;
    -- payments_made and status are intentionally mutable.
    RETURN NEW;
END;
$$;
