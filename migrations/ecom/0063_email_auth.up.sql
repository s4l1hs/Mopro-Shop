-- 0063_email_auth.up.sql
-- Adds email+password auth and phone-based MFA to users.
-- Keeps phone_hash/phone_enc for legacy phone-OTP sessions; new columns are for email flow.

-- phone_hash/enc are now nullable — email-only users have no phone.
ALTER TABLE identity_schema.users
  ALTER COLUMN phone_hash DROP NOT NULL,
  ALTER COLUMN phone_enc  DROP NOT NULL;

ALTER TABLE identity_schema.users
  ADD COLUMN IF NOT EXISTS email_hash     BYTEA UNIQUE,
  ADD COLUMN IF NOT EXISTS email_enc      TEXT,
  ADD COLUMN IF NOT EXISTS password_hash  TEXT,
  ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS mfa_enabled    BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS mfa_phone_hash BYTEA,
  ADD COLUMN IF NOT EXISTS mfa_phone_enc  TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS users_email_hash_idx
  ON identity_schema.users(email_hash)
  WHERE email_hash IS NOT NULL;

-- 6-digit codes sent to email for verification (account creation + email change).
CREATE TABLE IF NOT EXISTS identity_schema.email_verifications (
  id         BIGSERIAL PRIMARY KEY,
  user_id    BIGINT      NOT NULL REFERENCES identity_schema.users(id) ON DELETE CASCADE,
  code_hash  TEXT        NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ev_user_expires_idx
  ON identity_schema.email_verifications(user_id, expires_at DESC)
  WHERE used_at IS NULL;

-- Opaque tokens sent by email for password reset.
CREATE TABLE IF NOT EXISTS identity_schema.password_resets (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT      NOT NULL REFERENCES identity_schema.users(id) ON DELETE CASCADE,
  token_hash  TEXT        NOT NULL UNIQUE,
  expires_at  TIMESTAMPTZ NOT NULL,
  used_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ephemeral challenge issued during login when MFA is enabled.
-- Client holds the opaque challenge_token; backend holds challenge_hash + code_hash.
CREATE TABLE IF NOT EXISTS identity_schema.mfa_challenges (
  id             BIGSERIAL PRIMARY KEY,
  user_id        BIGINT      NOT NULL REFERENCES identity_schema.users(id) ON DELETE CASCADE,
  challenge_hash TEXT        NOT NULL UNIQUE,
  code_hash      TEXT        NOT NULL,
  expires_at     TIMESTAMPTZ NOT NULL,
  verified_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS mfa_chal_hash_idx
  ON identity_schema.mfa_challenges(challenge_hash)
  WHERE verified_at IS NULL;

-- Extend the otp_codes purpose check to include mfa_enroll.
ALTER TABLE identity_schema.otp_codes
  DROP CONSTRAINT IF EXISTS otp_codes_purpose_check;
ALTER TABLE identity_schema.otp_codes
  ADD CONSTRAINT otp_codes_purpose_check
    CHECK (purpose = ANY (ARRAY['login'::text, 'step_up'::text, 'mfa_enroll'::text]));

GRANT SELECT, INSERT, UPDATE ON identity_schema.email_verifications TO identity_user;
GRANT USAGE, SELECT ON identity_schema.email_verifications_id_seq TO identity_user;
GRANT SELECT, INSERT, UPDATE ON identity_schema.password_resets TO identity_user;
GRANT USAGE, SELECT ON identity_schema.password_resets_id_seq TO identity_user;
GRANT SELECT, INSERT, UPDATE ON identity_schema.mfa_challenges TO identity_user;
GRANT USAGE, SELECT ON identity_schema.mfa_challenges_id_seq TO identity_user;
