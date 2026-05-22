ALTER TABLE cashback_schema.plans
  DROP COLUMN IF EXISTS product_id,
  DROP COLUMN IF EXISTS product_title,
  DROP COLUMN IF EXISTS product_image_url;
