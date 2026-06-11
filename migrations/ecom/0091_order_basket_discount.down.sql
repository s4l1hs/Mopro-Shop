-- 0091_order_basket_discount.down.sql
ALTER TABLE order_schema.orders
  DROP COLUMN IF EXISTS discount_minor;

ALTER TABLE order_schema.order_items
  DROP COLUMN IF EXISTS basket_discount_pct,
  DROP COLUMN IF EXISTS list_unit_price_minor;
