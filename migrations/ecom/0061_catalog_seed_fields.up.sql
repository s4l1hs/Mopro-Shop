-- 0061_catalog_seed_fields.up.sql
-- Adds optional display fields required by the L2 seed script and catalog API.
-- Designed as additive-only; existing rows default gracefully.

ALTER TABLE catalog_schema.variants
    ADD COLUMN IF NOT EXISTS discount_price_minor BIGINT
        CHECK (discount_price_minor IS NULL OR (discount_price_minor >= 0 AND discount_price_minor < price_minor));

ALTER TABLE catalog_schema.products
    ADD COLUMN IF NOT EXISTS rating_stars  REAL NOT NULL DEFAULT 0.0,
    ADD COLUMN IF NOT EXISTS rating_count  INT  NOT NULL DEFAULT 0;

ALTER TABLE catalog_schema.product_translations
    ADD COLUMN IF NOT EXISTS specs JSONB NOT NULL DEFAULT '{}';

-- Global SKU uniqueness: external SKUs (e.g. barcodes) must be world-unique.
-- If cross-product duplicates already exist, this migration will fail — resolve manually first.
CREATE UNIQUE INDEX IF NOT EXISTS variants_sku_uq ON catalog_schema.variants (sku);
