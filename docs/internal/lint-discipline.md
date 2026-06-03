# Discipline linters — discovery + design (TOOLING_AUDIT T3-4 / T-007)

Catalogue of the four discipline patterns Steps 1–2 enforced by hand.

> **STATUS:** migration-safety shipped in PR #71 (text). **This PR (`cmd/lint-discipline`)
> builds 2 of the 3 flow-AST checks — pool-acquire-inside-tx + soft-deleted-user-consumer —
> on `golang.org/x/tools/go/analysis`, both at 0 findings (required drift-gates in
> `make verify`).** idempotency-surface remains SPLIT to a focused follow-up (the hardest;
> SQL-shape analysis, FP-prone — §6 / §4.1.5).

## The four patterns

### 1. Migration safety — SHIPPED (this PR)
Destructive DDL in a forward (`*.up.sql`) migration without a soft-deprecation
window. **Tractable as a text check** with one essential nuance discovery found:
- `*.down.sql` legitimately DROPs (it reverses the up) — **95 DROPs live there**;
  flagging them would be all false positives. Scan **`*.up.sql` only**.
- `ALTER COLUMN … DROP NOT NULL` *relaxes* a constraint (safe, backward-compatible)
  — must NOT be flagged. `… SET NOT NULL` is the risky one (fails on existing
  nulls / table rewrite). The repo has 2 `DROP NOT NULL` (safe), 0 `SET NOT NULL`.
- Current risky count in `*.up.sql`: **0** → the gate is green with an empty
  baseline (ratchet against future drift). Built as `scripts/lint-migrations.sh`
  (text/SQL — `go/analysis` is the wrong tool; it parses Go AST, not `.sql`).

### 2. Pool-acquire-inside-tx — ✅ BUILT (`cmd/lint-discipline/pooltx`)
`*pgxpool.Pool` method (Exec/Query/Acquire/Begin/…) called, within a function,
AFTER that pool's `Begin`/`BeginTx` opened a tx (PR #42 / #47 — pool exhaustion →
deadlock). Implementation (position-ordered, same-function — sound for the real
straight-line bug shape): flag pool calls after the first `Begin` **unless** a
`Commit`/`Rollback` occurs between (tx already closed) or the call is in a `defer`
(post-commit cleanup). A goroutine launched after Begin IS flagged (PR #42 did).
5 analysistest cases incl. the dlq.go pattern (pool use after Rollback = ok — a
real FP the canary caught + the analyzer now excludes). **0 codebase findings.**

### 3. Soft-deleted-user-consumer — ✅ BUILT (`cmd/lint-discipline/softdeleteduser`)
A `*Repository` user read (`Get*`/`Find*` bound to a non-blank var) inside a
function with no `StatusDeleted` guard (PR #49). Scoped to **Repository** receivers
on purpose: consuming the **service** (`svc.GetMe`) is safe — the service guards
internally — so those are NOT flagged (the discovery-caught FP). Discarded users
(`_, err := …`) and `Create*`/`Mark*` (fresh users) are excluded; `repository.go`,
`*_test.go`, and `//nolint:soft-deleted-user-consumer` funcs are exempt. 5
analysistest cases. **0 codebase findings** (service methods all guard post-#49).

### 4. Idempotency-surface — ⏳ STILL SPLIT (next follow-up)
An `INSERT` into a financial table without `ON CONFLICT` / a preceding
`SELECT … FOR UPDATE`. The hardest, highest-FP of the four (SQL-shape analysis of
`Exec` args + tx context). Per §4.1.5 it ships continue-on-error / disabled-by-
default — deferred to its own focused PR rather than rushed into this bundle.

## Why go/analysis (not grep), and 0 findings
The arc's rule (PRs #57–#71): an FP-ridden gate that cries wolf is worse than no
gate. Both shipped analyzers had real FPs on first run (pool: dlq.go post-Rollback;
soft-deleted: handlers consuming the guarding `svc.GetMe`) — each fixed by a precise
guard, landing at **0 findings**. So no baseline file is needed: the gate is a plain
required check (`make lint-discipline` in `verify`) that fails on any NEW finding,
suppressible via `//nolint:soft-deleted-user-consumer` where intentional.

## Remaining follow-up
`cmd/lint-discipline/idempotency` — the third `*analysis.Analyzer`, with
`analysistest` + (likely) continue-on-error until its baseline is triaged.
