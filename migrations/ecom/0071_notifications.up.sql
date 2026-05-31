-- 0071_notifications.up.sql — user-facing notification inbox (core-svc).
--
-- New core-svc module `internal/inbox` owns `inbox_schema` (decision: keep the
-- user inbox separate from jobs-svc's notification_schema, which holds only the
-- Slack-drift dedup table). Bootstrap (20-schemas/10-roles/30-grants) creates
-- the schema+role for fresh deploys; this CREATE SCHEMA IF NOT EXISTS covers
-- already-initialised clusters. user_id is a plain BIGINT (no cross-schema FK to
-- identity_schema.users — same convention as order_schema.orders).

CREATE SCHEMA IF NOT EXISTS inbox_schema;

CREATE TABLE IF NOT EXISTS inbox_schema.notifications (
    id          BIGSERIAL   PRIMARY KEY,
    user_id     BIGINT      NOT NULL,
    type        TEXT        NOT NULL
                CHECK (type IN ('order_status','return_update','security','marketing','system')),
    title_key   TEXT        NOT NULL,
    body_key    TEXT        NOT NULL,
    body_params JSONB       NOT NULL DEFAULT '{}'::jsonb,
    deep_link   TEXT,
    is_read     BOOLEAN     NOT NULL DEFAULT false,
    read_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
    ON inbox_schema.notifications (user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
    ON inbox_schema.notifications (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS inbox_schema.notification_preferences (
    user_id    BIGINT      NOT NULL,
    category   TEXT        NOT NULL,  -- notification.type values + 'general'
    channel    TEXT        NOT NULL CHECK (channel IN ('in_app','email','push')),
    enabled    BOOLEAN     NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, category, channel)
);

CREATE TABLE IF NOT EXISTS inbox_schema.push_tokens (
    id         BIGSERIAL   PRIMARY KEY,
    user_id    BIGINT      NOT NULL,
    token      TEXT        NOT NULL,
    platform   TEXT        NOT NULL CHECK (platform IN ('web','android','ios')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT push_tokens_token_uq UNIQUE (token)
);
CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON inbox_schema.push_tokens (user_id);
