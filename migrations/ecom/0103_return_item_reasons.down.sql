-- 0103_return_item_reasons.down.sql
ALTER TABLE order_schema.return_items
    DROP COLUMN IF EXISTS reason,
    DROP COLUMN IF EXISTS note;
