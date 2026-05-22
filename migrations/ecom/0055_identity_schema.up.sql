-- 0055_identity_schema_up.sql — identity_schema: users, otp_codes, refresh_tokens, devices (Phase 4.2a)
-- Depends on: identity_schema created by postgres-ecom/init/20-schemas.sql
--             identity_user granted by postgres-ecom/init/30-grants.sql
--             order_schema.outbox created by postgres-ecom/init/60-outbox.sql

-- ── Users ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS identity_schema.users (
    id          BIGSERIAL    PRIMARY KEY,
    phone_hash  BYTEA        NOT NULL,
    phone_enc   TEXT         NOT NULL,
    email_enc   TEXT,
    name        TEXT         NOT NULL DEFAULT '',
    locale      TEXT         NOT NULL DEFAULT 'tr-TR',
    status      TEXT         NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'suspended', 'deleted')),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ
);

-- Unique index on phone_hash is the primary lookup path (no plaintext stored unencrypted).
CREATE UNIQUE INDEX IF NOT EXISTS users_phone_hash_idx
    ON identity_schema.users(phone_hash);

CREATE INDEX IF NOT EXISTS users_status_idx
    ON identity_schema.users(status)
    WHERE status != 'deleted';

-- Auto-update updated_at on row change.
CREATE OR REPLACE FUNCTION identity_schema.touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'users_updated_at'
          AND tgrelid = 'identity_schema.users'::regclass
    ) THEN
        CREATE TRIGGER users_updated_at
            BEFORE UPDATE ON identity_schema.users
            FOR EACH ROW EXECUTE FUNCTION identity_schema.touch_updated_at();
    END IF;
END;
$$;

-- ── OTP codes ─────────────────────────────────────────────────────────────────
-- purpose: 'login' for initial auth, 'step_up' for high-sensitivity operations.
-- code_hash: bcrypt(cost=10) of the 6-digit plaintext code.
-- Only the latest unverified OTP per (phone_hash, purpose) is treated as valid.
CREATE TABLE IF NOT EXISTS identity_schema.otp_codes (
    id           BIGSERIAL    PRIMARY KEY,
    phone_hash   BYTEA        NOT NULL,
    purpose      TEXT         NOT NULL DEFAULT 'login'
                     CHECK (purpose IN ('login', 'step_up')),
    code_hash    TEXT         NOT NULL,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at   TIMESTAMPTZ  NOT NULL,
    verified_at  TIMESTAMPTZ
);

-- Service looks up latest active OTP for (phone_hash, purpose).
CREATE INDEX IF NOT EXISTS otp_codes_lookup_idx
    ON identity_schema.otp_codes(phone_hash, purpose, expires_at DESC)
    WHERE verified_at IS NULL;

-- ── Refresh tokens ────────────────────────────────────────────────────────────
-- token_hash: hex(SHA-256(64-char random opaque token)).
-- family_root: hex identifier shared by every token in a rotation chain.
--   On theft detection (revoked token reused), RevokeTokenFamily sets
--   revoked_at WHERE family_root = $1 AND revoked_at IS NULL.
CREATE TABLE IF NOT EXISTS identity_schema.refresh_tokens (
    id             BIGSERIAL    PRIMARY KEY,
    user_id        BIGINT       NOT NULL REFERENCES identity_schema.users(id),
    token_hash     TEXT         NOT NULL,
    family_root    TEXT         NOT NULL,
    issued_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at     TIMESTAMPTZ  NOT NULL,
    revoked_at     TIMESTAMPTZ,
    revoked_reason TEXT         CHECK (revoked_reason IN ('rotation', 'logout', 'theft', 'admin', 'expired'))
);

CREATE UNIQUE INDEX IF NOT EXISTS refresh_tokens_hash_idx
    ON identity_schema.refresh_tokens(token_hash);

-- Fast family revocation (O(1) scan bounded by family size, not full table).
CREATE INDEX IF NOT EXISTS refresh_tokens_family_idx
    ON identity_schema.refresh_tokens(family_root)
    WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS refresh_tokens_user_idx
    ON identity_schema.refresh_tokens(user_id, expires_at DESC)
    WHERE revoked_at IS NULL;

-- ── Devices ───────────────────────────────────────────────────────────────────
-- Stores FCM tokens for push notification delivery (jobs-svc reads via event).
-- One user may have multiple active devices; revoked_at marks deregistered devices.
CREATE TABLE IF NOT EXISTS identity_schema.devices (
    id            BIGSERIAL    PRIMARY KEY,
    user_id       BIGINT       NOT NULL REFERENCES identity_schema.users(id),
    fcm_token     TEXT         NOT NULL,
    device_model  TEXT         NOT NULL DEFAULT '',
    os_version    TEXT         NOT NULL DEFAULT '',
    registered_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    revoked_at    TIMESTAMPTZ
);

-- One active FCM token per device (dedup: revoke old record if same fcm_token re-registers).
CREATE UNIQUE INDEX IF NOT EXISTS devices_fcm_active_idx
    ON identity_schema.devices(fcm_token)
    WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS devices_user_idx
    ON identity_schema.devices(user_id)
    WHERE revoked_at IS NULL;

-- ── Explicit grants (belt-and-suspenders: ALTER DEFAULT PRIVILEGES covers future tables) ──
GRANT SELECT, INSERT, UPDATE, DELETE ON identity_schema.users         TO identity_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON identity_schema.otp_codes     TO identity_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON identity_schema.refresh_tokens TO identity_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON identity_schema.devices       TO identity_user;
GRANT USAGE, SELECT ON identity_schema.users_id_seq          TO identity_user;
GRANT USAGE, SELECT ON identity_schema.otp_codes_id_seq      TO identity_user;
GRANT USAGE, SELECT ON identity_schema.refresh_tokens_id_seq TO identity_user;
GRANT USAGE, SELECT ON identity_schema.devices_id_seq        TO identity_user;
