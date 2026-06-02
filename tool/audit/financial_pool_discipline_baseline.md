# Financial Domain Pool Discipline — Engine Review (CLAUDE.md §12)

Branch `fix/financial-domain-pool-discipline`. Base `main@802bfed9` (PR #42 GetAccountCurrencies,
PR #43 GetSystemState, PR #44 ImageMagick+bytes_of all merged).

## Headline finding — the deadlock surface is ONE shared function

Every financial ledger write funnels through **`wallet.PostInTx`**:
- cashback `run_month.go:203` → `walletPoster.PostInTx(ctx, tx, …)` (inside cashback `WithTx`)
- sellerpayout `run_daily.go:232` → `walletPoster.PostInTx(ctx, tx, …)` (inside sellerpayout `WithTx`)
- orderledger `service.go:143` → `wallet.PostInTx(ctx, tx, …)` (inside orderledger `WithTx`)

So the "pool-read inside a tx" deadlock pattern lives almost entirely in `PostInTx`, not per-domain.
PR #42/#43 already fixed its two routable reads. The remaining one is a deliberate pool read.

## §2.1 PR #42/#43 coverage (unchanged here)
- `GetAccountCurrencies(ctx, tx, …)` — **tx-routing** (PR #42). Stays.
- `GetSystemState(ctx, tx)` via `checkReadOnly(ctx, tx)` — **tx-routing** (PR #43). Stays.

## §2.4 Classification table

| Location | Current shape | Class | Action this PR |
|----------|---------------|-------|----------------|
| `wallet.GetAccountCurrencies` | reads calling tx | tx-routing | none (done #42) |
| `wallet.GetSystemState` | reads calling tx | tx-routing | none (done #43) |
| **`wallet.GetTransactionByIdempotencyKey`** (`service.go:121`, PostInTx 23505 replay path, inside the tx) | **pool** | **documented-pool-access** | **doc comment + contract regression test** |
| `sellerpayout.FindBatchByKey` (`run_daily.go:92`) | **pool, PRE-CHECK before `WithTx` (line 119)** | read-snapshot-before-tx (already) | none — already correct; cite as the pattern example |
| `sellerpayout.FindPayoutByKey` | pool | n/a | none — **no production caller** (interface/repo/mock only); note as dead |
| `orderledger.PostCapture` | `WithTx` → `wallet.PostInTx`; idempotency via PostInTx's UNIQUE key | n/a (inherits PostInTx) | none — no own in-tx pool read |
| `cashback` payment path | pre-checks outside tx + `wallet.PostInTx` | n/a (inherits PostInTx) | none |
| `reconcile.recordDrift` | `WithTx` writes only (`InsertAlertWithOutboxAndState(ctx, tx, …)`); cross-schema reads are verification reads outside any tx | n/a | none — out of scope (verification module, no in-tx pool read) |

### Why `GetTransactionByIdempotencyKey` is `documented-pool-access` (not tx-routable, not hoistable)
- It runs on the **23505 duplicate-replay path** *inside* `PostInTx`'s tx: after `InsertTransaction`'s
  SAVEPOINT rolls back on a unique violation, the lookup fetches the **sibling's just-committed**
  transaction id. The calling tx's snapshot (taken at tx open) cannot see a concurrently-committed
  row → tx-routing would return not-found and **break the idempotency contract**.
- It is **not** hoistable to `read-snapshot-before-tx`: the lookup is *conditional on* the in-tx
  duplicate detection, which only manifests during the insert attempt.
- It is **the only remaining in-tx pool read** across the financial write surface.

## §1.6 escape-hatch checks
- **#3 (third domain):** does NOT fire. orderledger is a third financial domain, but it shares
  `wallet.PostInTx` rather than having its own in-tx idempotency lookup — so it's not a separate
  pattern to fix. sellerpayout's lookup is a pre-check outside the tx. No 3+ separate patterns.
- **#1 (deeper redesign):** not needed. The classifications resolve cleanly without advisory locks
  or a read-pool (both explicit non-goals).

## §2.6 Production concurrency
- All three writers run as **singleton crons / single-consumer event handlers** (cashback monthly
  cron, sellerpayout daily cron, orderledger `ecom.order.paid` consumer — one fin-svc binary).
  No non-singleton manual-replay path found for `PostInTx`. Prod stays safe; the regression test
  guarantees correctness under arbitrary concurrency regardless.

## §2.5 Non-fragile regression test design
PR #42's `MaxConns=1` guard was CI-fragile (a legit op exceeded a tight deadline under load) and
was dropped. Replacement shape:
- Pin `MaxConns=4` (the CI default that exposed the original deadlock; not over-constrained).
- N=8 concurrent `PostInTx` calls (same idempotency key → exercises both the winner path and the
  replay path), with randomized 1–10ms delays to broaden the contention surface.
- Assert **no deadlock** via a `context.WithTimeout(15s)` + done-channel select (fail loudly on hang),
  not "max 1 connection per goroutine."
- Use native **`pgxpool.Stat`** (AcquireCount/ReleaseCount delta) for a leak check — no custom
  wrapper, survives pgx version bumps.
- `-count=20` in CI.
Plus a `documented-pool-access` contract test: N concurrent same-key attempts → exactly one inserts,
all N observe the same txn id (this assertion depends on the pool read; tx-routing would break it).

## Scope conclusion (diverges from the prompt's premise)
No `tx-routing` additions and no `read-snapshot-before-tx` *migrations* are needed — they're already
in place (#42/#43, and sellerpayout's pre-check). This PR's substance is: **(1) document the one
`documented-pool-access` read, (2) the two non-fragile regression tests, (3) CONTRIBUTING patterns +
decision tree.** No code behavior change.
