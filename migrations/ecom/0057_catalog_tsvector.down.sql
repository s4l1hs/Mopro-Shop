DROP INDEX IF EXISTS catalog_schema.product_translations_search_vector_idx;
ALTER TABLE catalog_schema.product_translations DROP COLUMN IF EXISTS search_vector;
