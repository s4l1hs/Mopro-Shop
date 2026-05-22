-- 0055_identity_schema_down.sql — drop identity_schema tables (Phase 4.2a)
-- WARNING: irreversible data loss. Only use in dev/test environments.

DROP TABLE IF EXISTS identity_schema.devices         CASCADE;
DROP TABLE IF EXISTS identity_schema.refresh_tokens  CASCADE;
DROP TABLE IF EXISTS identity_schema.otp_codes       CASCADE;
DROP TABLE IF EXISTS identity_schema.users           CASCADE;
DROP FUNCTION IF EXISTS identity_schema.touch_updated_at CASCADE;
