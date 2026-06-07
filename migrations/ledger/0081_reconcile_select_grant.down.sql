-- 0081_reconcile_select_grant.down.sql
-- Revoke the SELECT added by the up migration (DELETE from init/73 is untouched).
REVOKE SELECT ON wallet_schema.event_delivery_attempts FROM reconcile_user;
