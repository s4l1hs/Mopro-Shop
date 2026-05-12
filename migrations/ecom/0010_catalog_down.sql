-- 0010_catalog_down.sql — roll back catalog_schema tables (dev only)
-- ORDER MATTERS: drop child tables first to avoid FK violations.

DROP TABLE IF EXISTS catalog_schema.variants CASCADE;
DROP TABLE IF EXISTS catalog_schema.product_translations CASCADE;
DROP TABLE IF EXISTS catalog_schema.products CASCADE;
