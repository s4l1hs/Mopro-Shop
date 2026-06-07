-- 0081_reconcile_select_grant.up.sql
-- F-019: grant reconcile_user SELECT on wallet_schema.event_delivery_attempts.
-- reconcile.CleanupOldAttempts runs `DELETE … WHERE attempt_at < now()-'7 days'`;
-- PostgreSQL needs SELECT to evaluate the WHERE predicate, so DELETE-alone (init/73)
-- throws 42501 every weekly cron run (alert noise + the table never prunes).
-- DELETE is already granted (init/73); this adds only the missing SELECT (least
-- privilege). The fresh-DB source (deploy/postgres-ledger/init/73) is updated in
-- lockstep; this migration carries already-deployed databases across the same change.
-- IDEMPOTENT: GRANT is a no-op if the privilege is already held.
GRANT SELECT ON wallet_schema.event_delivery_attempts TO reconcile_user;
