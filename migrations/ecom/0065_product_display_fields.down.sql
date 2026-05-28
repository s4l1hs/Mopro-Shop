DROP INDEX IF EXISTS catalog_schema.products_rating_idx;
ALTER TABLE catalog_schema.variants
  DROP COLUMN IF EXISTS original_price_minor;
ALTER TABLE catalog_schema.products
  DROP COLUMN IF EXISTS rating_count,
  DROP COLUMN IF EXISTS rating_avg;
