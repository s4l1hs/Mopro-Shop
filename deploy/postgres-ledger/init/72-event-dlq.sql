-- Migration 72: Dead-Letter Queue for permanently-failed Redis Streams events.
--
-- wallet_user (fin-svc dispatch path): SELECT, INSERT.
-- dlq_user   (mopro CLI):             SELECT, INSERT, UPDATE(status columns).
-- reconcile_user:                     no access (DLQ is operational, not financial).

CREATE TABLE IF NOT EXISTS wallet_schema.event_dlq (
    id                   BIGSERIAL    PRIMARY KEY,
    original_topic       TEXT         NOT NULL,
    original_message_id  TEXT         NOT NULL,
    consumer_group       TEXT         NOT NULL,
    idempotency_key      TEXT         NOT NULL,
    -- Full raw Redis stream entry fields (msg.Values JSON-serialised). Always
    -- populated regardless of whether payload parse succeeds, so operators
    -- can inspect malformed events.
    payload              JSONB        NOT NULL,
    attempt_count        INTEGER      NOT NULL,
    -- JSON array: [{attempt_at, consumer_name, outcome, error?}], last ≤10 entries.
    -- Populated once at INSERT from event_delivery_attempts + current attempt row.
    -- Never mutated after creation (attempt_at of prior entries may lag by one
    -- async-worker cycle; attempt_count is authoritative).
    error_history        JSONB        NOT NULL DEFAULT '[]',
    status               TEXT         NOT NULL DEFAULT 'open'
                             CHECK (status IN ('open', 'replayed', 'dismissed')),
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- Replay lifecycle: populated by `mopro dlq replay`.
    replayed_at          TIMESTAMPTZ,
    replayed_by          TEXT,
    -- Redis message_id produced by the replay XADD; links to new attempt rows.
    replayed_message_id  TEXT,
    -- Dismiss lifecycle: operator decision to never replay this event.
    dismissed_at         TIMESTAMPTZ,
    dismissed_by         TEXT,
    dismissal_reason     TEXT,
    -- Idempotent DLQ inserts: the same (group, messageID) pair can only be
    -- DLQed once per consumer group. XAUTOCLAIM re-delivery after a failed
    -- XACK hits ON CONFLICT DO NOTHING, avoiding duplicate rows.
    UNIQUE (consumer_group, original_message_id)
);

-- For: SELECT * FROM event_dlq WHERE original_topic=$1 AND created_at > now()-'10m'
-- (SEV2 storm rate check; also used by `mopro dlq list --since`).
CREATE INDEX IF NOT EXISTS event_dlq_topic_time
    ON wallet_schema.event_dlq (original_topic, created_at);

-- Hot path: `mopro dlq list` (default status=open); operator dashboard.
CREATE INDEX IF NOT EXISTS event_dlq_open
    ON wallet_schema.event_dlq (status, original_topic)
    WHERE status = 'open';

-- For: `mopro dlq replay --idempotency-key <k>` lookups.
CREATE INDEX IF NOT EXISTS event_dlq_idem
    ON wallet_schema.event_dlq (idempotency_key);

-- ── dlq_user role (mopro CLI) ────────────────────────────────────────────────
-- Least privilege: cannot touch financial tables, can only operate on the DLQ.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dlq_user') THEN
        CREATE ROLE dlq_user WITH LOGIN PASSWORD 'dlq_changeme_in_prod';
    END IF;
END $$;

GRANT USAGE ON SCHEMA wallet_schema TO dlq_user;

-- CLI reads + inserts rows (insert needed for bulk replay if CLI ever pre-creates retry rows;
-- primary INSERT path is wallet_user via fin-svc dispatch).
GRANT SELECT, INSERT ON wallet_schema.event_dlq TO dlq_user;

-- CLI updates lifecycle columns only; financial columns (payload, error_history,
-- attempt_count, etc.) are immutable after creation.
GRANT UPDATE (status, replayed_at, replayed_by, replayed_message_id,
              dismissed_at, dismissed_by, dismissal_reason)
    ON wallet_schema.event_dlq TO dlq_user;

-- CLI inspect: read prior attempt history for a DLQ row.
GRANT SELECT ON wallet_schema.event_delivery_attempts TO dlq_user;

GRANT USAGE, SELECT ON SEQUENCE wallet_schema.event_dlq_id_seq TO dlq_user;

-- ── wallet_user grants (fin-svc dispatch path) ───────────────────────────────
GRANT SELECT, INSERT ON wallet_schema.event_dlq TO wallet_user;
GRANT USAGE, SELECT ON SEQUENCE wallet_schema.event_dlq_id_seq TO wallet_user;
