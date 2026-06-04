-- 0081_products_free_shipping.down.sql
ALTER TABLE catalog_schema.products
  DROP COLUMN IF EXISTS free_shipping;
