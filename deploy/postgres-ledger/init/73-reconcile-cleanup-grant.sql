-- Migration 73: Allow reconcile_user to delete stale event_delivery_attempts rows.
-- reconcile.WeeklyCron runs a cleanup step that DELETEs rows older than 7 days.
-- This prevents unbounded table growth without requiring a separate DBA operation.
-- SELECT is required too: PostgreSQL evaluates the DELETE's WHERE (attempt_at)
-- predicate, so DELETE alone throws 42501 (F-019). Migration 0081 carries this
-- SELECT to already-deployed DBs; this init line keeps fresh DBs in lockstep.
GRANT SELECT, DELETE ON wallet_schema.event_delivery_attempts TO reconcile_user;
