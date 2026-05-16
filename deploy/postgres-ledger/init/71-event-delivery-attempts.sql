-- 71-event-delivery-attempts.sql — tracks every Redis Streams message dispatch outcome.
-- Used by Phase 3.1 WARN-at-3 DLQ candidate detection and Phase 3.2 DLQ insertion.
-- Lives in wallet_schema (eventbus infrastructure owned by fin-svc).

CREATE TABLE IF NOT EXISTS wallet_schema.event_delivery_attempts (
    id              BIGSERIAL PRIMARY KEY,
    stream          TEXT NOT NULL,
    message_id      TEXT NOT NULL,
    consumer_group  TEXT NOT NULL,
    consumer_name   TEXT NOT NULL,
    attempt_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    outcome         TEXT NOT NULL CHECK (outcome IN ('success', 'error', 'panic')),
    error_message   TEXT,
    duration_ms     INTEGER
);

-- Lookup index: used by CountFailures (stream + message_id + consumer_group).
CREATE INDEX IF NOT EXISTS event_delivery_attempts_lookup
    ON wallet_schema.event_delivery_attempts (stream, message_id, consumer_group);

-- Cleanup index: used by future retention job to purge old records.
CREATE INDEX IF NOT EXISTS event_delivery_attempts_cleanup
    ON wallet_schema.event_delivery_attempts (attempt_at);

-- Explicit grants (belt-and-suspenders — DEFAULT PRIVILEGES in 30-grants.sql already covers
-- tables created after that file ran, but explicit grants are safer for patch migrations).
GRANT SELECT, INSERT, DELETE ON wallet_schema.event_delivery_attempts TO wallet_user;
GRANT USAGE, SELECT ON SEQUENCE wallet_schema.event_delivery_attempts_id_seq TO wallet_user;
