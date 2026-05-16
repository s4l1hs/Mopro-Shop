-- Migration 73: Allow reconcile_user to delete stale event_delivery_attempts rows.
-- reconcile.WeeklyCron runs a cleanup step that DELETEs rows older than 7 days.
-- This prevents unbounded table growth without requiring a separate DBA operation.
GRANT DELETE ON wallet_schema.event_delivery_attempts TO reconcile_user;
