-- 0084_seller_dispatch_origin.down.sql — reverse 0084.
ALTER TABLE seller_schema.sellers DROP COLUMN IF EXISTS dispatch_city;
