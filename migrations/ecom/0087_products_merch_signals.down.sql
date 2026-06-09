-- 0087_products_merch_signals.down.sql
ALTER TABLE catalog_schema.products
  DROP COLUMN IF EXISTS basket_discount_pct,
  DROP COLUMN IF EXISTS is_bestseller;
