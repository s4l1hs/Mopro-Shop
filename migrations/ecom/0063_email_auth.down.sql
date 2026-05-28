DROP TABLE IF EXISTS identity_schema.mfa_challenges;
DROP TABLE IF EXISTS identity_schema.password_resets;
DROP TABLE IF EXISTS identity_schema.email_verifications;
ALTER TABLE identity_schema.users
  DROP COLUMN IF EXISTS mfa_phone_enc,
  DROP COLUMN IF EXISTS mfa_phone_hash,
  DROP COLUMN IF EXISTS mfa_enabled,
  DROP COLUMN IF EXISTS email_verified,
  DROP COLUMN IF EXISTS password_hash,
  DROP COLUMN IF EXISTS email_enc,
  DROP COLUMN IF EXISTS email_hash;
