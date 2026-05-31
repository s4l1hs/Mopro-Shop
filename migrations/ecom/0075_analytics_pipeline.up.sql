-- 0075_analytics_pipeline.up.sql — Tranche 4a analytics pipeline (core-svc ingest
-- + jobs-svc aggregation/retention/erasure). New `analytics_schema`.
--
-- Per TRANCHE_4_DESIGN.md Decision 2 (append-only log + derived projections) and
-- Decision 4 (merge via session_identity). All `user_id`/`product_id` columns are
-- plain BIGINT soft references — NO cross-schema FK to identity_schema.users or
-- catalog_schema.products (same convention as inbox_schema.notifications /
-- order_schema.orders, and required because DELETE /me is a SOFT delete so
-- ON DELETE CASCADE would never fire). Integrity is enforced at the app layer;
-- account-deletion erasure is event-driven (ecom.user.soft_deleted.v1 consumer).
--
-- Bootstrap (20-schemas/10-roles/30-grants) creates the schema+role for fresh
-- deploys; this CREATE SCHEMA IF NOT EXISTS covers already-initialised clusters
-- and the integration-test DB.

CREATE SCHEMA IF NOT EXISTS analytics_schema;

-- Append-only event log. Source of truth (Decision 2). Never UPDATE/DELETE
-- except the 90-day retention prune and the per-user erasure path.
CREATE TABLE IF NOT EXISTS analytics_schema.analytics_events (
    id              BIGSERIAL   PRIMARY KEY,
    session_id      TEXT        NOT NULL,            -- client-generated UUID, stable per browser session
    user_id         BIGINT,                          -- nullable for guest events; resolved via session_identity
    event_type      TEXT        NOT NULL,            -- one of the locked 20-event taxonomy (TRANCHE_4_DESIGN.md §2)
    payload         JSONB       NOT NULL DEFAULT '{}'::jsonb,
    client_ts       TIMESTAMPTZ NOT NULL,            -- when the event happened on the client
    server_ts       TIMESTAMPTZ NOT NULL DEFAULT now(),
    ingest_batch_id UUID                              -- groups events from one ingest request (debugging)
);
CREATE INDEX IF NOT EXISTS idx_events_session   ON analytics_schema.analytics_events (session_id, server_ts);
CREATE INDEX IF NOT EXISTS idx_events_user      ON analytics_schema.analytics_events (user_id, server_ts) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_events_type_ts   ON analytics_schema.analytics_events (event_type, server_ts);
CREATE INDEX IF NOT EXISTS idx_events_server_ts ON analytics_schema.analytics_events (server_ts);  -- retention prune

-- Session-identity resolution (Decision 4). Append-only; one session binds to
-- exactly one user (PK on session_id). Lets reads attribute guest events to a
-- user after login without mutating past events.
-- ACCOUNT_DELETION: cascade required — erased by the ecom.user.soft_deleted.v1 consumer.
CREATE TABLE IF NOT EXISTS analytics_schema.session_identity (
    session_id  TEXT        PRIMARY KEY,
    user_id     BIGINT      NOT NULL,                -- soft reference (no FK)
    resolved_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_session_identity_user ON analytics_schema.session_identity (user_id);

-- Consent state per user (Decision 3 — binary opt-in). Absence = no consent.
-- ACCOUNT_DELETION: cascade required.
CREATE TABLE IF NOT EXISTS analytics_schema.user_consent (
    user_id           BIGINT      PRIMARY KEY,        -- soft reference (no FK)
    analytics_enabled BOOLEAN     NOT NULL DEFAULT false,
    consented_at      TIMESTAMPTZ,
    revoked_at        TIMESTAMPTZ,
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Recently-viewed projection (Decision 2). Derived from product_view events;
-- upserted incrementally on ingest + rebuilt nightly as a drift backstop.
-- ACCOUNT_DELETION: cascade required.
CREATE TABLE IF NOT EXISTS analytics_schema.user_recently_viewed (
    user_id        BIGINT      NOT NULL,              -- soft reference (no FK)
    product_id     BIGINT      NOT NULL,              -- soft reference (no FK)
    last_viewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    view_count     INTEGER     NOT NULL DEFAULT 1,
    PRIMARY KEY (user_id, product_id)
);
CREATE INDEX IF NOT EXISTS idx_recently_viewed_user_ts
    ON analytics_schema.user_recently_viewed (user_id, last_viewed_at DESC);
