# Financial Core Discipline

The conventions financial-path code MUST follow, consolidated from CLAUDE.md §4–5,
CONTRIBUTING, and the PR-by-PR lessons in REPORT.md. Each is enforced by a
**perpetual gate** (a CI analyzer/test) or by **manual review**. Read this once;
the review checklist at the end is the PR-time TL;DR.

Scope: `internal/{wallet,cashback,sellerpayout,commission,treasury,ledger,
orderledger,outbox,reconcile,payment}` and any code touching ledger state, money
movement, or PSP integration.

## Conventions

### 1. SERIALIZABLE for ledger writes, with bounded retry
**Why:** ledger postings race under contention; phantom reads / lost updates would
break the double-entry invariant (CLAUDE.md §4.1).
**Rule:** a transaction that mutates ledger state runs at `pgx.Serializable` and
retries a bounded number of times on `40001` (serialization_failure) / `40P01`
(deadlock). Plan *reads*/creation may use `ReadCommitted`.
```go
// cashback per-plan cron tx (see internal/cashback/api.go's documented level note)
err := dbRetrySerializable(ctx, pool, func(tx pgx.Tx) error {
    return repo.ClaimPaymentPeriod(ctx, tx, in) // all writes inside the tx
})
```
**Gating:** integration/property suites (`property-cashback`, `property-payout`) +
indirectly the pool-acquire analyzer (#2). **Precedent:** PR #42 (cashback deadlock).

### 2. No pool-acquire inside a tx scope
**Why:** acquiring a *new* pool connection while a tx is open can exhaust the pool
and deadlock the cron (the original #42 incident).
**Rule:** between `pool.Begin/BeginTx` and the matching `Commit`/`Rollback`, use
**`tx`** for all DB calls — never the `*pgxpool.Pool`.
```go
tx, _ := pool.Begin(ctx)
defer tx.Rollback(ctx)
_, _ = tx.Exec(ctx, "...")   // ✅ tx
// _, _ = pool.Exec(ctx, "...")  // ❌ pool while tx open → flagged
tx.Commit(ctx)
_, _ = pool.Exec(ctx, "...")  // ✅ pool after commit (or in post-commit defer)
```
**Gating:** **required** — `cmd/lint-discipline` `pool-acquire-inside-tx` (PR #71/#72), 0 findings.
**Precedent:** PR #42, #47.

### 3. Soft-deleted-user consumer guard
**Why:** a soft-deleted user must not be acted on; the guard lives in the service
(the repo is a dumb store), so consumers reading the repo directly must check.
**Rule:** a `*Repository` user read (`Get*`/`Find*`) used in a function must be
guarded by `Status == StatusDeleted` (or go through the guarding service method).
```go
u, _ := repo.GetUser(ctx, id)
if u.Status == identity.StatusDeleted { return ErrUserDeleted }
// ... use u
```
**Gating:** **required** — `cmd/lint-discipline` `soft-deleted-user-consumer` (PR #71/#72), 0 findings.
Exempt via `//nolint:soft-deleted-user-consumer` for admin/audit reads.
**Precedent:** PR #49 (GetMe deleted-user hole).

### 4. Idempotency at the storage layer
**Why:** financial writes must be safe to retry (cron re-runs, webhook redelivery).
**Rule:** every financial INSERT either (a) carries a UNIQUE key + `ON CONFLICT …
DO NOTHING/UPDATE`, or (b) is preceded by `SELECT … FOR UPDATE` on the idempotency
key in the same tx. Cron keys: `cashback:<plan>:<YYYYMM>`, `payout:<payout_id>`.
```sql
INSERT INTO wallet_schema.event_dlq (..., idempotency_key)
VALUES (..., $1)
ON CONFLICT (consumer_group, original_message_id) DO NOTHING   -- idempotent re-entry
```
**Gating:** the `idempotency-surface` analyzer is a **pending** `cmd/lint-discipline`
follow-up (split per PR #72); **manual review** until it lands.
**Precedent:** PR #58 (reconciler atomicity), CLAUDE.md §4.4.

### 5. Transactional outbox
**Why:** a state change + its external event must be atomic — no "wrote ledger,
crashed before emitting" (CLAUDE.md §4.5).
**Rule:** the ledger write and the `outbox` row insert happen in the **same tx**;
`outbox.idempotency_key` is UNIQUE; a separate publisher XADDs to Redis Streams;
consumers dedupe on the key.
```go
dbRetrySerializable(ctx, pool, func(tx pgx.Tx) error {
    if _, err := repo.PostInTx(ctx, tx, ledgerMove); err != nil { return err }
    return outbox.InsertInTx(ctx, tx, event) // same tx → atomic
})
```
**Gating:** the load-bearing `integration-e2e` + outbox integration tests (PR #58); no static analyzer.
**Precedent:** PR #58.

### 6. Rate-limiter zset members are unique per request
**Why:** a sliding-window limiter keyed on a bare millisecond timestamp collapses a
same-ms burst to one zset element → the cap is under-enforced (a sub-ms bypass).
**Rule:** the Lua `ZADD` member is `<now_ms>:<uuid>` (unique), while the *score*
stays `now_ms` for window trimming.
```lua
redis.call('ZADD', key, now_ms, member)  -- member = ARGV[4] = "<now_ms>:<uuid>"
```
**Gating:** identity rate-limiter integration tests, incl. same-ms burst (PR #61); no static analyzer.
**Precedent:** PR #61 (F-017 — and the F-016 misdiagnosis it corrected: the cause was the
zset member, not shared test-Redis).

### 7. Soft references across services
**Why:** cross-service FKs create distributed-tx surface; soft refs let each service
evolve its schema independently (CLAUDE.md §5).
**Rule:** cross-schema references are `BIGINT`, **no FK**, dereferenced via the owning
module's `Service` interface (or the event/outbox seam) — never a cross-schema JOIN
(except `ref_schema`, and `internal/reconcile` which is the documented exception).
**Gating:** `scripts/check-module-boundaries.sh` (cross-module imports) + manual review for SQL.
**Precedent:** CLAUDE.md §5; PR #8 (`CaptureRecorder` cross-module seam).

### Note — prod-safety guards read INJECTED config (not `os.Getenv`)
Financial adapters with a production-startup invariant (e.g. sipay refusing a sandbox key when
`Environment=="production"`) encode the environment in **injected config**, not a direct
`os.Getenv` — so the guard is unit-testable and the process-kill happens at the caller (`main`),
not buried in the adapter. The env-read lives once at the binary entry. **Precedent:** A-003 / A4-3
(sipay `SipayConfig.Environment`, shipping `inProduction`, identity `WithDevOTPBypass`).

### 8. Price-history tracking (TR/EU lowest-30-day)
**Why:** TR 6502 + EU Omnibus (2019/2161) require that an announced price reduction show the
lowest price applied in the 30 days before the reduction — compliant display needs a temporal
record of every price a product was offered at.
**Rule:** every variant price-set is recorded in `catalog_schema.variant_price_history`. Tracking is
a **database trigger** (`variants_price_history_trg`, "Mechanism B") — not application code — because
the dominant write path is SQL seeds and the Go `InsertVariant` does not even set
`original_price_minor`; a trigger captures seed, app, import, and any future update path uniformly.
`lowest_30d_price_minor` is read as an inline `MIN(price_minor) … WHERE effective_at >= now()-30d`
correlated subquery on the product summary (no batch method; mirrors `favorites_count`).
**Gating:** integration tests (`internal/catalog/price_history_integration_test.go`) + migration-safety
(`scripts/lint-migrations.sh`). Triggers are intentionally outside `lint-discipline` (it observes Go,
not DDL); the convention is documented here instead.
**Limits:** today `lowest_30d == current price` for every product (prices are immutable
post-creation — the price-update lifecycle is **P-032**), and the static `variants.original_price_minor`
strikethrough is **not** substantiated by history (frontend display + legal review pending). This is the
technical foundation, **not** a compliance sign-off.
**Precedent:** P-030 (`feat/price-history`, migration 0083); `docs/internal/p030-price-history-architecture.md`.

## Gating summary

| Convention | Perpetual gate | Manual review |
|---|---|---|
| 1. SERIALIZABLE retry | property/integration suites | yes |
| 2. Pool-acquire-inside-tx | `lint-discipline` (required) | no |
| 3. Soft-deleted-user | `lint-discipline` (required) | no |
| 4. Idempotency surface | analyzer **pending** | yes |
| 5. Outbox | integration tests | yes |
| 6. Rate-limiter zset member | integration tests | yes |
| 7. Soft refs | boundary script (imports only) | yes |
| 8. Price-history tracking | integration tests + migration-safety | yes |

## Review checklist (PRs touching financial-domain code)

- [ ] Ledger-mutating tx uses `SERIALIZABLE` + bounded retry on 40001/40P01.
- [ ] No `*pgxpool.Pool` call between `BeginTx` and `Commit`/`Rollback`.
- [ ] Every cross-schema user read checks soft-delete status (or uses the guarding service).
- [ ] Every financial INSERT has an idempotency mechanism (UNIQUE+`ON CONFLICT` or `FOR UPDATE`).
- [ ] State change that emits an event writes the event to `outbox` in the same tx.
- [ ] Any new rate-limiter uses unique zset members (`<ts>:<unique>`).
- [ ] Cross-service refs use the soft-ref convention (BIGINT, no FK, deref via Service).
- [ ] Any path that sets a variant price is covered by the price-history trigger (or documents why not).

## Related
- `CLAUDE.md` §4 (financial invariants) + §5 (DB/soft-ref rules) — the constitution.
- `cmd/lint-discipline/` — the analyzers gating conventions 2 & 3 (`docs/internal/lint-discipline.md`).
- `docs/audits/TESTING_AUDIT.md` (Step 2), `docs/audits/ARCHITECTURE_AUDIT.md` (Step 4).
- `REPORT.md` — the authoritative PR-by-PR history behind each "Precedent".
