package outbox

// TODO(mopro:placeholder): implement outbox relay worker — reads undelivered rows from
// outbox table and XADDs to Redis Streams via internal/eventbus.
// Unblocked by: Phase 1 (DB + Redis wiring) and Phase 0.2 (outbox schema migration)
