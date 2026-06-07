# F-019 — reconcile_user SELECT grant + reconcile suite revival (discovery)

> Fixes the live prod `42501` F-018 surfaced; revives F-018's 10th suite. Source-verified
> 2026-06-07 on branch. Confirms grant state, table, role, migration head, fixture path.

## 1. The bug (quoted)

`deploy/postgres-ledger/init/73-reconcile-cleanup-grant.sql` — **DELETE only, no SELECT**:
```sql
GRANT DELETE ON wallet_schema.event_delivery_attempts TO reconcile_user;
```
`internal/reconcile/repository.go` `CleanupOldAttempts` (the weekly cron's maintenance step):
```sql
DELETE FROM wallet_schema.event_delivery_attempts WHERE attempt_at < now() - INTERVAL '7 days'
```
PostgreSQL requires **SELECT** to evaluate a DELETE's `WHERE` predicate (it reads `attempt_at`),
so `reconcile_user` — with DELETE but not SELECT — throws **`42501 permission denied`** every
weekly cron run in prod: the error lands in `result.Errors` (alert noise) and the table never
prunes (unbounded growth). **Reproduced on a fresh `pg-ledger-test` fixture** (grants =
`{DELETE}` only): `TestReconcileIntegration_CleanDB_BothCheckPass` fails with exactly this 42501.

Least privilege: the statement needs **SELECT + DELETE**. DELETE is already granted, so the fix is
**SELECT only** — no other privilege added.

## 2. Table, role, schema, migration head (confirmed)

- Table: `wallet_schema.event_delivery_attempts` (created init/71, schema-qualified).
- Role: `reconcile_user` (created init/69 with read-only cross-schema SELECT grants — the §5
  reconcile exception; init/72 adds dlq_user SELECT; init/73 adds reconcile_user DELETE).
- Ledger migration head: **0080** → new migration is **0081**.

## 3. Fixture grant-path (the revival's correctness hinge)

`make pg-ledger-test-up` (Makefile:187–194) applies **`deploy/postgres-ledger/init/*.sql` THEN
`migrations/ledger/*.up.sql`** to the `pg-ledger-test` :6434 container. So the revived suite will
see the new grant via **either** the init/73 update **or** migration 0081 — both land. (Updating
both is still required for the real targets: init/* provisions fresh DBs; 0081 carries the
already-deployed prod DB across on `ledger up`.) Same for `pg-ledger-e2e` (Makefile:429+), though
the reconcile suite targets :6434.

## 4. Suite wiring — framing shift vs the prompt

The prompt's §3.2 says "delete the legacy self-spinning target." **There is none** — `grep` shows
no `test-integration-reconcile` / `integration-reconcile` target ever existed. reconcile is in the
#103 **"no target"** group, not the **"colliding target"** group. So revival is purely **additive**:
one env-pointer target, no deletion. The suite already reads `LEDGER_TEST_DSN` (admin, default
:6434) + `RECONCILE_TEST_DSN` (reconcile_user, default :6434) with `t.Skip` on unreachable — the
exact env-pointer shape of the other 9. Its sole blocker was the grant (§1), now confirmed.

No `TRUNCATE` needed: the reconcile suite manages its own ledger rows per-test (it tests drift
detection by inserting/clearing); no shared-fixture residue class like outbox/idempotency (#108).
Will re-validate on a torn-down-and-rebuilt fixture per §4 anyway.

## 5. Plan

1. this doc · 2. migration `0081_reconcile_select_grant.{up,down}.sql` + init/73 converged ·
3. `integration-reconcile` target + verify registration · 4. make verify + REPORT + TESTING_AUDIT
(F-019 FIXED, F-018 10/10) + PR. Prod 42501 stops when 0081 rides the deploy-runway `ledger up`.
