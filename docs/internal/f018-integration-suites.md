# F-018 Discovery — Reviving the 10 Unwired Integration Suites (§2)

> The 10 `//go:build integration` suites found dark in the #103 sweep (`docs/internal/
> integration-tests-wiring.md` §4), now triaged **empirically**: every suite was RUN against the
> real containers on 2026-06-07. Statuses below are evidence, not guesses.

## 1. The proven harness pattern (what green suites do)

Two idempotent-reuse container fixtures already in the `verify` chain:
- **`e2e-test-up`** → `pg-ecom-e2e` :6435 (empty; suites self-bootstrap), `pg-ledger-e2e` :6436
  (init + all ledger migrations), `redis-e2e` :6381.
- **`pg-ledger-test-up`** → `pg-ledger-test` :6434 (init + all ledger migrations) — used by the
  property/wallet targets.

Green targets are env-pointer one-liners: `integration-<pkg>: e2e-test-up` + `<PKG>_TEST_DSN=…`
+ `go test -tags=integration -count=1 -race -timeout 5m ./internal/<pkg>/...`.

**Discovery shift vs. the prompt:** no dynamic-port helper is needed. The collision was never in
the suites — almost all already read env-DSNs **whose `:6434` defaults point exactly at
`pg-ledger-test`**. The collisions live in the LEGACY self-spinning make targets
(`test-integration-order` binds :6435 = pg-ecom-e2e; `test-integration-{outbox,sellerpayout}`
bind :6434 = pg-ledger-test; legacy `test-integration-cart` binds :6380 and duplicates the wired
`integration-cart`). The §3.1 "keystone fix" = **delete the legacy targets, add env-pointer
targets on the shared fixtures** — the cart/identity revival pattern, applied 9 more times.

## 2. Per-suite triage (all empirical, `-race -count=1`)

| # | Suite | Needs | Run result | Terminal status |
|---|---|---|---|---|
| 1 | `internal/attachments` (`MEDIA_TEST_DSN`; applies 0079 down/up itself) | pg-ecom | **PASS** | **FIX** — target only |
| 2 | `internal/help` (`HELP_TEST_DSN`; self-bootstraps help_schema) | pg-ecom | **PASS** | **FIX** — target only |
| 3 | `internal/inbox` (`INBOX_TEST_DSN`; self-bootstraps inbox_schema) | pg-ecom | **PASS** | **FIX** — target only |
| 4 | `internal/idempotency` (`REDIS_URL`, redis:// form, DB 15) | redis | **PASS** | **FIX** — target only |
| 5 | `internal/eventbus` (autoclaim + dlq + dlq_e2e; `REDIS_TEST_ADDR`+`LEDGER_TEST_DSN`, skip-if-down) | redis + pg-ledger | **PASS** | **FIX** — target only |
| 6 | `internal/sellerpayout` full (`SELLERPAYOUT_TEST_DSN`, skip-if-down; `-skip Property` — Property already runs in `property-payout`) | pg-ledger | **PASS** | **FIX** — target only |
| 7 | `internal/outbox` (`publisher_test.go`) | pg-ledger + redis | not yet runnable: DSN/addr are **hardcoded consts** (`:6434`/`:6380`), `os.Exit(1)` no-skip | **FIX** — add env override (mirror eventbus's helpers; harness-only, no assertion change) + target |
| 8 | `internal/order` full (`ORDER_TEST_DSN`; TestMain self-bootstraps) | pg-ecom | **FAIL ×3** — `column "seller_id" does not exist`: TestMain DDL predates **0059_orders_v8** (`seller_id`, `checkout_session_id` on orders); repo scans them (`COALESCE(seller_id,0)`) | **FIX** — add the two v8 columns to the TestMain DDL (bootstrap matches current schema; assertions untouched) + target |
| 9 | `internal/api` fin (`LEDGER_TEST_DSN`) | pg-ledger | **FAIL ×4** — `finSeedPlan` INSERT violates `plans.price_minor NOT NULL` (column added by a later cashback migration; seed helper predates it) | **FIX** — add `price_minor` to the seed INSERT (seed helper, not assertion) + target |
| 10 | `internal/reconcile` (`LEDGER_TEST_DSN`+`RECONCILE_TEST_DSN`, skip-if-down; needs `reconcile_user` from init/69) | pg-ledger | **FAIL** — `permission denied for table event_delivery_attempts` (42501) in `CleanupOldAttempts` | **DEFER — blocked on a REAL PRODUCT GAP** (below) |

9/10 FIX (6 pure-wiring + 3 harness-touch), 1 DEFER. None NOT-ACTIONABLE — nothing tests deleted
code; nothing is duplicate.

## 3. The reconcile finding — production bug, filed (F-019)

`init/73-reconcile-cleanup-grant.sql` grants reconcile_user **`DELETE`-only** on
`wallet_schema.event_delivery_attempts`. PostgreSQL requires **`SELECT`** to evaluate a DELETE's
WHERE predicate, so `repository.go CleanupOldAttempts` (`DELETE … WHERE attempt_at < now()-'7 days'`)
throws 42501 — **reproduced directly against the DB as reconcile_user**, independent of any test.
The weekly reconcile cron's maintenance step (service.go:63) hits this **in production** every run
(the error lands in `result.Errors` → alerting noise; attempts rows never get pruned).

Fix (out of scope here — SUT change): one-line `GRANT SELECT` — as a **ledger migration** (init
scripts don't re-run on existing clusters, so prod needs the migration path) + the same line in
init/73 for fresh clusters. Filed as **TESTING_AUDIT F-019**; suite revival follows in the F-018
batch-2 PR once merged. This bug is exactly the class F-018 exists to surface: the suite that
would have caught it ran in no gate.

## 4. Sequencing + isolation notes

- Suites on the **shared** clusters self-bootstrap idempotently; `order`'s TestMain
  DROP+CREATEs `order_schema.{orders,order_items,outbox}` — destructive to tables `payment`'s and
  `e2e`'s suites also build. Safe because `verify`'s integration chain is **sequential** (no `-j`
  in CI) and each TestMain rebuilds what it needs; revived targets are appended **after** the
  existing chain to keep today's ordering unchanged.
- `verify` runtime cost (measured): attachments/help/inbox/idempotency/order/api ≈ 1–2 s each;
  eventbus ≈ 30 s (autoclaim waits); sellerpayout ≈ 8 s. Total ≈ +45 s.
- Legacy targets to delete: `test-integration-{order,sellerpayout,outbox,cart}` (cart is a stale
  duplicate of the wired `integration-cart`; the other three are the port-colliders).
  `test-integration-catalog` stays (own port :6433, wired, green).

## 5. Commit plan

1. this doc · 2. outbox env-override + order DDL + apifin seed (harness fixes) ·
3. Makefile: 9 targets + legacy deletions + `verify` registration · 4. REPORT/queue closure.
All 9 fit one PR (≈150 LOC total vs 400 ceiling); reconcile carried as F-019 + batch-2.
