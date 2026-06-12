# ADR 0003: Redis Streams MAXLEN Policy

- **Status:** Accepted
- **Date:** 2026-05-11
- **Phase introduced:** Phase 0 (Prompt 0.4)
- **Decided by:** Mopro architecture
- **Related:** ARCHITECTURE.md § 5, LEDGER_GUIDE.md § 5, CLAUDE.md § 3, ADR-0001

## Context

The outbox pattern decouples durability from delivery:

- **Durability layer:** `wallet_schema.outbox` (postgres-ledger) and `order_schema.outbox` (postgres-ecom). Rows survive process crashes because they live in PostgreSQL.
- **Delivery layer:** Redis Streams. The outbox publisher XADDs rows to Redis; consumers XREADGROUP from Redis. Redis is ephemeral by design (AOF replay re-fills it after restart).

Redis Streams trim their length when `MAXLEN` is specified in an XADD call. Once a stream entry is trimmed, it is gone from Redis. If a consumer group has not yet XACK'd that entry, the consumer will miss it permanently — the outbox row is already marked `published_at = now()` and will not be re-published.

This creates a data-loss scenario: `MAXLEN` too low + slow/offline consumer = permanently missed events.

## Decision

**Default MAXLEN: `~ 10000` (approximate trim, all streams).**

The `~` prefix uses Redis approximate trimming (O(1) per XADD) rather than exact trimming (O(N)). At 100 orders/minute, 10 000 entries = ~100 minutes of buffer before the oldest entry is trimmed.

**Per-stream env-configurable override mechanism:**

```
REDIS_STREAM_MAXLEN_<STREAM_UPPER_DOTS_TO_UNDERSCORES>=<value>
```

Examples:
```
REDIS_STREAM_MAXLEN_ECOM_ORDER_DELIVERED_V1=25000
REDIS_STREAM_MAXLEN_ECOM_PAYMENT_CAPTURED_V1=25000
REDIS_STREAM_MAXLEN_FIN_CASHBACK_PAYMENT_POSTED_V1=10000
```

Implemented in `redis_bus.go::maxLenFor(topic)`. Default 10 000 if the override env var is absent or invalid.

**Production recommendations (documented in `.env`):**

| Stream | Recommended MAXLEN | Reasoning |
|---|---|---|
| `ecom.order.delivered.v1` | 25 000 | Financial trigger for cashback + payout; ~4 hours at 100 ord/min |
| `ecom.payment.captured.v1` | 25 000 | Financial trigger; same retention target |
| `fin.cashback.payment.posted.v1` | 10 000 | Notification only; duplicates are low-impact |
| `fin.seller.payout.posted.v1` | 10 000 | Notification only |
| All others | 10 000 | Default |

## Consequences

### Positive
- Per-stream tuning without code change: ops can increase MAXLEN for critical streams independently
- Approximate trimming is O(1) — no XADD latency penalty at high volume
- Default of 10 000 limits Redis memory growth to ~10–50 MB per stream under normal load
- Env-configurable approach is consistent with the market/currency config-driven philosophy (CLAUDE.md § 2.2)

### Negative
- `MAXLEN` is a memory-retention trade-off, not a durability guarantee. If a consumer lags behind MAXLEN entries, it permanently misses those events from the delivery layer
- Unlike Kafka's replicated log, Redis Streams with MAXLEN is lossy for very slow consumers
- Operators must consciously set higher values for financial trigger streams

### Mitigations
- The **outbox table** is the authoritative durability layer. An offline consumer that missed trimmed Redis entries can be replayed via `mopro outbox replay --since "<downtime-start>"` (Phase 3.3 — the replay CLI re-publishes rows by re-setting `published_at = NULL` for the affected window)
- Phase 3.3 adds `mopro_outbox_lag_seconds` metric and an alert if lag exceeds 60 seconds, giving operators early warning before MAXLEN is approached
- The `~` (approximate) trim mode means Redis will sometimes retain slightly more than MAXLEN entries, increasing the practical buffer window

## Alternatives Considered

1. **MAXLEN = 0 (no trim):** Streams grow unbounded. With AOF replay, Redis memory usage is proportional to total unprocessed events. At 100 orders/day and no consumer downtime this is negligible; but an extended consumer outage (days) would grow Redis beyond the 800 MB `maxmemory` limit and trigger eviction of key-value data. Rejected for Phase 0.4; revisit in Phase 3 if consumer lag becomes a persistent concern.

2. **Single global MAXLEN env var:** Simpler but cannot protect financial trigger streams differently from notification streams. Rejected in favour of per-stream granularity.

3. **Exact trimming (`MAXLEN` without `~`):** O(N) per XADD. At high throughput this adds measurable latency. Rejected; approximate trim is sufficient and standard.

## Revisit

Phase 3.3 (Outbox Publisher Productionize):
- After `mopro outbox replay` CLI is implemented, the replay safety net makes higher MAXLEN values less critical for financial streams
- Add consumer group lag monitoring (`XINFO GROUPS` → consumer `lag` field) to auto-alert when any group approaches MAXLEN
- Evaluate increasing defaults to 100 000 for financial streams based on observed peak lag in production
