# fin-svc harness + cron-overlap sim — discovery (TOOLING_AUDIT cron-sim)

**Outcome: BLOCKED / NOT-ACTIONABLE for now** (the §4.2.1 decision-tree's blocked
branch). The cron-overlap sim is not built; this documents why, honestly.

## What the crons actually are
`scripts/cashback-monthly-cron.sh` / `seller-payout-daily-cron.sh` are thin
wrappers that **`curl` a fin-svc internal HTTP endpoint**:
```
curl -X POST http://localhost:8082/internal/v1/cashback/run-monthly  -H "Authorization: Bearer $ADMIN_INTERNAL_TOKEN" ...
```
So a cron-**overlap** sim means: fire that endpoint twice concurrently against a
**running fin-svc** + its `postgres-ledger` + auth, and assert no double-application.

## Why a safe harness is blocked
1. **No HTTP integration harness for fin-svc exists.** fin-svc is a binary
   (`cmd/fin-svc`); today's fin tests are *module-level* (`internal/cashback`,
   `internal/sellerpayout`, `internal/wallet` against `pg-ledger-test`), not a
   booted HTTP service. Standing up `cmd/fin-svc` on `:8082` with config + the
   internal router + auth is a substantial new harness.
2. **No mock/test-mode PSP.** `internal/payment/` has only real adapters
   (`sipay`, `craftgate`, `iyzico`) — `grep mock|fake|sandbox` → none. The
   **seller-payout** cron initiates a real PSP transfer; running it against a live
   fin-svc with no PSP test-mode would hit (or need credentials for) a real gateway.
   That's the §4.2.1 `BLOCKED-BY-MISSING-TEST-MODE` condition.

## And the value would be marginal
The overlap risk the sim targets — double-application under concurrent cron runs —
is **already gated** below the HTTP layer:
- cashback monthly: idempotent via `UNIQUE (plan_id, period_yyyymm)` + key
  `cashback:<plan>:<YYYYMM>` (CLAUDE.md §4.4); exercised by
  `internal/cashback/cashback_cron_integration_test.go`.
- seller payout: idempotency-key = `payout:<payout_id>` + the append-only ledger
  invariants (CLAUDE.md §4.4 / §4.8).
A booted-HTTP overlap sim would mostly re-test those constraints one layer up.

## Recommendation (filed as a finding)
**T-016 — fin-svc lacks an HTTP integration harness + a mock-PSP test mode.** This
is product-adjacent infrastructure (a `payment` test adapter + a fin-svc boot
harness), not tooling — a **Step 4** candidate. When it exists, the cron-overlap
sim (`scripts/sim-cron-overlap.sh`) becomes a small consumer on top of it.
