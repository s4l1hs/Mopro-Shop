-- 0079_payments_made_cache_comment.up.sql
-- Documents cashback_schema.plans.payments_made as a denormalized cache
-- after the storage-layer idempotency refactor in this PR. The source of
-- truth is now cashback_schema.payments (UNIQUE(plan_id, period_yyyymm)),
-- and the cron's RefreshPaymentsMadeCache rewrites this column from
-- COUNT(*) FROM payments WHERE plan_id=X AND status='paid' inside the same
-- SERIALIZABLE tx that flips the payment row to 'paid'.
--
-- Readers MAY query payments_made for the common-case fast path (e.g.
-- ListDuePlans's start_date + payments_made*1mo predicate), but anything
-- that needs authoritative state (audit, reconcile, partial-refund flow)
-- MUST count the payments table directly.

COMMENT ON COLUMN cashback_schema.plans.payments_made IS
    'Denormalized cache of COUNT(*) FROM cashback_schema.payments WHERE plan_id=plans.id AND status=''paid''. The payments table is the source of truth (UNIQUE(plan_id, period_yyyymm) is the cron idempotency guard). The cache is refreshed atomically inside the SERIALIZABLE tx that flips each payment row to ''paid''. Do not treat as authoritative — for audit/reconcile/refund flows, count the payments table directly.';
