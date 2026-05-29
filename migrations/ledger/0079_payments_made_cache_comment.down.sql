-- 0079_payments_made_cache_comment.down.sql
-- Clear the COMMENT added by the up migration. Passing NULL drops the comment.

COMMENT ON COLUMN cashback_schema.plans.payments_made IS NULL;
