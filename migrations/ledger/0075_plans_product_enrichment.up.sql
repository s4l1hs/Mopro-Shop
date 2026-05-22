-- 0075_plans_product_enrichment.up.sql — Phase 4.4a tech debt: snapshot product metadata
-- into cashback_schema.plans so the wallet screen can show product name + image.
-- Columns are nullable: existing rows have NULL (frontend falls back to "Sipariş #<id>").
-- plans_immutable trigger extended below to block UPDATE on these columns once set.

ALTER TABLE cashback_schema.plans
  ADD COLUMN IF NOT EXISTS product_id         BIGINT,
  ADD COLUMN IF NOT EXISTS product_title       TEXT,
  ADD COLUMN IF NOT EXISTS product_image_url   TEXT;

-- Extend the immutability trigger to cover the new columns.
-- Replace the existing function body (CREATE OR REPLACE is safe).
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
    -- product snapshot columns: immutable once set (not-null → not-null transition blocked)
    (OLD.product_id       IS NOT NULL AND OLD.product_id       IS DISTINCT FROM NEW.product_id) OR
    (OLD.product_title    IS NOT NULL AND OLD.product_title    IS DISTINCT FROM NEW.product_title) OR
    (OLD.product_image_url IS NOT NULL AND OLD.product_image_url IS DISTINCT FROM NEW.product_image_url)
  ) THEN
    RAISE EXCEPTION 'cashback_schema.plans: immutable column update attempted';
  END IF;
  RETURN NEW;
END;
$$;
