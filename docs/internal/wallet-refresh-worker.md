# `wallet.RefreshWorker` — discovery (TESTING_AUDIT F-003)

A thin background worker that periodically refreshes the wallet balance materialized
view. Far simpler than the reconciler (PR #58) — no queue, no lease, no events.

## Real path
`internal/wallet/refresh_worker.go`. `RefreshWorker{pool, interval, log}`;
`NewRefreshWorker(pool, interval, log)` (interval ≤ 0 → 1h default).

## Responsibilities
- `Run(ctx)` — a `time.Ticker(interval)` loop: on each tick call `refresh`; on
  `ctx.Done()` log + return. **Void return** (no error surfaced from the loop).
- `RefreshOnce(ctx) error` — single `refresh` (the unit other code/tests call).
- `refresh(ctx) error` — `REFRESH MATERIALIZED VIEW CONCURRENTLY wallet_schema.balances`.

## Contract / shape
- **Trigger:** an embedded ticker, started as `go worker.Run(ctx)` in wiring.
- **State:** read/writes only the MV (Postgres `REFRESH MATERIALIZED VIEW CONCURRENTLY`
  is itself atomic + serialized by PG; the strict-balance source of truth is unaffected).
- **Idempotency:** trivially idempotent — refreshing twice yields the same MV. No lease,
  no `FOR UPDATE SKIP LOCKED`, no outbox. Two concurrent `REFRESH … CONCURRENTLY` are
  serialized by Postgres (one waits).
- **Transactional shape:** none at the app level (single statement; PG-internal).
- **External calls:** none.
- **Soft-delete:** N/A — it never reads users/subjects; it refreshes an aggregate MV.
- **Failure model:** `Run` logs a refresh error and **continues** (retry next tick); a
  transient/failed refresh never crashes the loop. No dead-letter (nothing to letter).

## What F-003 covers (and what's N/A)
Existing `TestIntegration_RefreshWorker` covers `RefreshOnce` (→ MV updates). **Untested:**
the `Run` ticker loop, its cancel/shutdown path, and its error-resilience. This PR adds:
- **Unit** (`refresh_worker_test.go`, no DB): `Run` exits promptly on `ctx` cancel when the
  interval is long enough that no tick fires (nil pool never touched — proves the
  select/shutdown path in isolation).
- **Integration** (on the new `integration-wallet` gate): `Run` with a short interval
  actually refreshes the MV (post a txn → MV catches up after a tick); and `Run` survives a
  failing pool (refresh errors are logged, the loop keeps going and exits on cancel).

N/A cases (documented, not fabricated): concurrent-exactly-once / lease-expiry /
soft-deleted-subject / outbox-atomicity — none exist for an idempotent MV-refresher.
