-- 0076_cashback_accelerated_v8.down.sql
-- Reverses the v8 migration. Restores the v6 immutability trigger.

-- 1. Drop new constraints.
ALTER TABLE cashback_schema.plans
    DROP CONSTRAINT IF EXISTS plans_principal_exact,
    DROP CONSTRAINT IF EXISTS plans_payments_within_total,
    DROP CONSTRAINT IF EXISTS plans_last_gte_monthly,
    DROP CONSTRAINT IF EXISTS plans_monthly_positive,
    DROP CONSTRAINT IF EXISTS plans_total_months_positive;

-- 2. Drop new columns.
ALTER TABLE cashback_schema.plans
    DROP COLUMN IF EXISTS payments_made,
    DROP COLUMN IF EXISTS monthly_amount_last_minor,
    DROP COLUMN IF EXISTS total_months,
    DROP COLUMN IF EXISTS commission_bps,
    DROP COLUMN IF EXISTS price_minor;

-- 3. Remove default from reference_interest_rate_bps.
ALTER TABLE cashback_schema.plans
    ALTER COLUMN reference_interest_rate_bps DROP DEFAULT;

-- 4. Drop unique index on order_id.
DROP INDEX IF EXISTS cashback_schema.plans_order_id_unique;

-- 5. Restore v6 immutability trigger (from 0075_plans_product_enrichment.up.sql).
CREATE OR REPLACE FUNCTION cashback_schema.plans_immutable_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (
    OLD.order_id                  IS DISTINCT FROM NEW.order_id OR
    OLD.user_id                   IS DISTINCT FROM NEW.user_id OR
    OLD.monthly_amount_minor      IS DISTINCT FROM NEW.monthly_amount_minor OR
    OLD.currency                  IS DISTINCT FROM NEW.currency OR
    OLD.reference_interest_rate_bps IS DISTINCT FROM NEW.reference_interest_rate_bps OR
    OLD.start_date                IS DISTINCT FROM NEW.start_date OR
    OLD.delivered_at              IS DISTINCT FROM NEW.delivered_at OR
    (OLD.product_id       IS NOT NULL AND OLD.product_id       IS DISTINCT FROM NEW.product_id) OR
    (OLD.product_title    IS NOT NULL AND OLD.product_title    IS DISTINCT FROM NEW.product_title) OR
    (OLD.product_image_url IS NOT NULL AND OLD.product_image_url IS DISTINCT FROM NEW.product_image_url)
  ) THEN
    RAISE EXCEPTION 'cashback_schema.plans: immutable column update attempted';
  END IF;
  RETURN NEW;
END;
$$;
