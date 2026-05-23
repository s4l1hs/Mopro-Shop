-- 0058_checkout_sessions.up.sql
-- Tracks multi-seller checkout sessions: one PSP payment → N per-seller orders.
-- The session id == PSP invoice_id so the webhook can resolve all order IDs.

CREATE TABLE IF NOT EXISTS order_schema.checkout_sessions (
    id              TEXT        PRIMARY KEY,   -- caller-supplied UUID = PSP invoice_id
    user_id         BIGINT      NOT NULL,
    reservation_id  TEXT        NOT NULL DEFAULT '',
    status          TEXT        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','psp_initiated','completed','failed','expired')),
    order_ids       BIGINT[]    NOT NULL DEFAULT '{}',
    amount_minor    BIGINT      NOT NULL,
    currency        TEXT        NOT NULL,
    provider_ref    TEXT        NOT NULL DEFAULT '', -- PSP invoice_id (= id after initiation)
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS checkout_sessions_user_idx
    ON order_schema.checkout_sessions (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS checkout_sessions_status_pending_idx
    ON order_schema.checkout_sessions (status)
    WHERE status IN ('pending', 'psp_initiated');
