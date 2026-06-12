-- 0095_checkout_installments.down.sql — reverse 0095_checkout_installments.up.sql
ALTER TABLE order_schema.checkout_sessions
  DROP COLUMN IF EXISTS installments;
