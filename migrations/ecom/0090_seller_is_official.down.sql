-- 0090_seller_is_official.down.sql
ALTER TABLE seller_schema.sellers DROP COLUMN IF EXISTS is_official;
