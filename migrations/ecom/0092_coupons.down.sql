-- 0092_coupons.down.sql — reverse 0092_coupons.up.sql
ALTER TABLE order_schema.orders
  DROP COLUMN IF EXISTS coupon_discount_minor,
  DROP COLUMN IF EXISTS coupon_code;

DROP TABLE IF EXISTS order_schema.coupon_redemptions;
DROP TABLE IF EXISTS order_schema.coupons;
