-- 90-notification-schema.sql — notification_schema tables.
-- Schema + role already created in 20-schemas.sql / 10-roles.sql / 30-grants.sql.
-- This file adds the slack_sent dedup table for the jobs-svc reconcile-drift consumer.

CREATE TABLE IF NOT EXISTS notification_schema.slack_sent (
    id               BIGSERIAL PRIMARY KEY,
    idempotency_key  TEXT        NOT NULL,
    topic            TEXT        NOT NULL,
    sent_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT slack_sent_idempotency_key_uq UNIQUE (idempotency_key)
);
