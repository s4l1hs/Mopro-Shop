# Discipline linters — discovery + design (TOOLING_AUDIT T3-4)

Catalogue of the four discipline patterns Steps 1–2 enforced by hand, and which
are tractable to automate now vs. deferred. **This PR ships migration-safety**
(text-tractable, low-FP); the three flow-sensitive AST checks are split to a
focused `cmd/lint-discipline` follow-up (see "Split" below).

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

### 2. Pool-acquire-inside-tx — DEFERRED (split)
`pgxpool.Pool` method called while a `tx` from `pool.BeginTx`/`dbx.InTx` is open
(PR #42 / #47 — exhausts the pool → deadlock). Detecting it **correctly** needs
flow analysis: a pool call is fine before `BeginTx` and in post-`Commit`/`Rollback`
cleanup, only risky *while the tx is live*. That is control/data-flow over
`go/analysis` (likely SSA), not a textual match — a grep version is FP/FN-ridden.

### 3. Soft-deleted-user-consumer — DEFERRED (split)
A user read that doesn't honour `Status == StatusDeleted` (PR #49). PR #49's design
puts the guard in the **service** (the repo is a dumb store), so the real check is
"a service method returning a user applies the guard" — flow-sensitive, and admin/
audit consumers are legitimate exemptions. Needs `go/analysis`, not grep.

### 4. Idempotency-surface — DEFERRED (split)
An `INSERT` into a financial table without `ON CONFLICT` / a preceding
`SELECT … FOR UPDATE`. Requires SQL-shape analysis of `Exec` call args + tx
context — the hardest, highest-FP of the four. `go/analysis` + continue-on-error.

## Why split 2–4 rather than ship grep heuristics
The arc's rule (PRs #57–#70): an FP-ridden gate that cries wolf is worse than no
gate — it trains people to ignore it. Checks 2–4 are each a careful `go/analysis`
`Analyzer` with `analysistest` fixtures (a focused PR, like T-001 was). Shipping
migration-safety well + cataloguing the rest honestly beats four shallow greps.
The prompt assumed 2–4 were "easy"; discovery says otherwise (the §2.3 hatch).

## Follow-up: `cmd/lint-discipline`
One Go binary, three `*analysis.Analyzer`s (pool-in-tx, soft-deleted-consumer,
idempotency-surface) + `analysistest` + a baseline; pool/soft-deleted gated,
idempotency continue-on-error initially (per the PR #63 day-one protocol).
