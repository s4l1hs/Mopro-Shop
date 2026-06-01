# Cashback PgxPool Deadlock — Engine Review (CLAUDE.md §12)

Branch `fix/cashback-pgxpool-deadlock`. Base `main@8b6d9fec` (PR #41 merged).
Origin: PR #41 make-verify CI → https://github.com/s4l1hs/Mopro-Shop/actions/runs/26772827566 (FAILURE).

## §2.1 Deadlock mechanism (confirmed in code)

Call chain: `PayMonthlyInstallments` → `payOnePlan` (SERIALIZABLE retry) → `payOnePlanInTx`
→ `repo.WithTx(pgx.Serializable, …)` → `wallet.PostInTx(ctx, tx, …)` →
`repo.GetAccountCurrencies(ctx, ids)` → **`r.pool.Query`** (`internal/wallet/repository.go:134`).

- The outer SERIALIZABLE tx holds **pool connection #1**.
- `GetAccountCurrencies` reads from the **pool**, acquiring **connection #2** while #1 is held.
- The test (`TestCronProperty_ConcurrentIdempotency`) fires up to **8 concurrent** `PayMonthlyInstallments` on a pool whose default `MaxConns = max(4, NumCPU)` = **4 on the 2-vCPU CI runner**.
- Cycle: up to 4 goroutines hold a tx conn (#1); the claim-winner needs conn #2 for `GetAccountCurrencies` but the pool is empty; the claim-losers hold their tx conn blocked on the winner's uncommitted `ClaimPaymentPeriod` row-lock; the winner can't commit/release #1 without #2 → **deadlock** → 600s package timeout. (Local 6-core → pool≥6 → masked.)

## §2.2 Pool-reads inside the `PostInTx` (tx-bearing) chain

| # | Read | File:line | In cashback deadlock? | Tx-routable? |
|---|------|-----------|------------------------|--------------|
| 1 | `GetAccountCurrencies` (defensive currency check) | `wallet/repository.go:134` | **YES — the source** | **YES** — accounts are resolved/committed *before* `WithTx` (`run_month.go`: `FindAccountByOwnerAnyStatus`/`OpenOrFindUserWallet` on the pool, pre-tx), so the SERIALIZABLE snapshot sees them. Adds only point-reads on rarely-mutated `accounts` rows to the tx's conflict scope (negligible extra 40001). |
| 2 | `GetTransactionByIdempotencyKey` (duplicate-replay) | `wallet/repository.go:99` | No (cashback's `ClaimPaymentPeriod` UNIQUE guard means only the claim-winner reaches `PostInTx`; the ledger idem-key is unique per winner) | **NO — must stay pool.** Reads a txn a *concurrent* tx may have committed **after** this SERIALIZABLE snapshot; a tx-read would return *not-found* → break idempotent-replay correctness. (`InsertTransaction` uses a SAVEPOINT, so the tx is healthy after 23505 — the blocker is snapshot visibility, not an aborted tx.) |
| 3 | `GetSystemState` (via `checkReadOnly`) | `wallet/repository.go:304` | Rarely (TTL-cached `sysStateTTL`, fail-open) | Safe to tx-route but low value; mostly cache hits. |

**This is the §12 payoff:** a naive "route every PostInTx read through the tx" would convert
read #2 into a correctness bug (idempotent replay returning not-found under concurrency). The
correct cashback fix is **read #1 only.**

## §2.3 Production concurrency

- Cashback monthly cron is a **singleton**: `cmd/fin-svc/main.go:264` `NewMonthlyCron(...).Start()`, single fin-svc binary.
- `PayMonthlyInstallments` processes plans **sequentially** (`run_month.go`: `for _, plan := range plans { payOnePlan }`) — no internal concurrency.
- No non-cron invocation path found (no manual-replay endpoint/admin tool calling `PayMonthlyInstallments`).
- ⇒ **Prod is safe today** by operational invariant: 1 cron × sequential × ≥2-conn-need vs pool≈6. The deadlock is **test-surfaced** (injected 8-way concurrency). The fix makes correctness independent of that invariant + unblocks make-verify CI.

## §2.4 Production pool size

- **No explicit pool config anywhere** (`grep MaxConns/DB_MAX_CONNS/pool_max` → only `pkg/metrics/pool.go` observability). ⇒ pgx default `max(4, NumCPU)` applies → **≈6 on the 6-vCPU prod VDS** (CLAUDE.md §1), **4 on the 2-vCPU CI runner**.
- Backlog (operational, not this PR): set an explicit `DB_MAX_CONNS` so the deadlock budget isn't CPU-count-implicit.

## §1.6 escape hatch — TRIGGER #1 FIRED (≥3 analogous patterns in financial paths)

1. wallet `GetAccountCurrencies` — **fixed here** (tx-routable).
2. wallet `GetTransactionByIdempotencyKey` — latent 2nd-conn on the replay path; **not tx-routable** (correctness). Needs a non-tx-routing approach.
3. wallet `GetSystemState` (checkReadOnly) — latent, TTL-cached.
4. sellerpayout `FindPayoutByKey` / `FindBatchByKey` (`sellerpayout/repository.go:70,147`) — same idempotency-lookup-via-pool shape; likely called inside the payout `WithTx` duplicate path. **Other domain.**

Per §1.6 #1: **this PR fixes the cashback path (read #1) only**; the rest carry to
`fix/financial-domain-pool-discipline` (a focused follow-up). Note #2 and #4 can't be fixed by
naive tx-routing (idempotency lookups must see concurrently-committed rows) — the follow-up
needs an architectural approach (e.g. a reserved connection, or restructuring the replay lookup),
which is exactly why it deserves separate review.

## Chosen fix shape (§3)

`GetAccountCurrencies(ctx, accountIDs)` → `GetAccountCurrencies(ctx, tx pgx.Tx, accountIDs)`:
non-nil tx → `tx.Query`; nil → `r.pool.Query` (backwards-compatible; mirrors the existing
nullable-tx convention at `repository.go:326` `SetSystemState`). `PostInTx` passes its own `tx`.
Rejected: a `…WithTx` sibling (two functions drift); context-bound tx (implicit, un-greppable).
