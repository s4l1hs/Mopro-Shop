-- 0094_checkout_installments.down.sql — reverse 0094_checkout_installments.up.sql
ALTER TABLE order_schema.checkout_sessions
  DROP COLUMN IF EXISTS installments;
