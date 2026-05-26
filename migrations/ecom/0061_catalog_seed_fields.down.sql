-- 0061_catalog_seed_fields.down.sql

DROP INDEX IF EXISTS catalog_schema.variants_sku_uq;

ALTER TABLE catalog_schema.product_translations DROP COLUMN IF EXISTS specs;
ALTER TABLE catalog_schema.products             DROP COLUMN IF EXISTS rating_count;
ALTER TABLE catalog_schema.products             DROP COLUMN IF EXISTS rating_stars;
ALTER TABLE catalog_schema.variants             DROP COLUMN IF EXISTS discount_price_minor;
