# `payment.Reconciler` — discovery (for TESTING_AUDIT F-001 test suite)

Discovery for the test suite that closes **TESTING_AUDIT F-001**. Read end-to-end on
`main@12dc496f`. This records what the reconciler *actually* does — several behaviours
differ from the generic assumptions in the F-001 fix prompt (noted inline).

## §2.1 Real path
- `internal/payment/reconciler.go` (177 lines), package `payment`.
- Type `Reconciler`, methods `Run`, `runOnce`, `reconcileOne` (+ free funcs
  `paymentEventTypeFromStatus`, `outboxEventFromStatus`).
- Wired live: `cmd/core-svc/main.go:265` `payment.NewReconciler(...)` → `go reconciler.Run(ctx)`.

## §2.2 Responsibilities
**What it reconciles:** payment intents stuck in `pending` past expiry, against the PSP.
It "catches webhooks that Sipay failed to deliver."
- **Trigger:** a goroutine ticking every `reconcilerInterval = 60s` (hard-coded const;
  `NewReconciler` accepts no interval — the field exists but only the const is used).
- **Read:** `repo.FindExpiredPendingPayments(ctx, 50)` → `order_schema.payments` where
  `status='pending' AND expires_at < NOW() - INTERVAL '2 minutes'`, `LIMIT 50`,
  `ORDER BY expires_at ASC`, `FOR UPDATE SKIP LOCKED`.
- **Per row:** `svc.CheckStatus(providerRef)` (PSP poll). If `pending`/`unknown` → leave
  for next pass. If `captured`/`failed`/`refunded` → in a tx: `repo.UpdatePaymentStatus`
  (sets the matching `captured_at`/`failed_at`/`refunded_at`) + `outboxRepo.Insert` a
  `ecom.payment.{captured,failed,refunded}.v1` event.
- **External call:** `svc.CheckStatus` (PSP HTTP) — **outside** the tx (good: no gateway
  call holds a DB tx open).
- **Failure model:** per-row errors are logged (`Warn`) and skipped — the pass continues;
  per-pass errors are logged (`Error`) and retried on the next tick. No dead-letter; a
  permanently-stuck row is simply retried every 60s forever (acceptable: PSP terminal
  status eventually resolves it, or ops intervenes).

## §2.3 Idempotency contract (differs from the prompt's "lease" assumption)
**There is no lease table / advisory lock.** Concurrency safety is two-layered:
1. `FOR UPDATE SKIP LOCKED` on the fetch → concurrent *simultaneous* fetches get disjoint
   row sets. **But** the fetch is a standalone query (not held through `reconcileOne`'s
   separate tx), so the row lock is released when `FindExpiredPendingPayments` returns —
   it reduces, doesn't eliminate, cross-instance double-fetch.
2. The **durable** guarantee is the outbox `idempotency_key UNIQUE` constraint
   (`deploy/postgres-ecom/init/60-outbox.sql:11`, key = `"reconcile:psp:" + providerRef`).
   `outbox.Insert` maps `23505` → `ErrDuplicateIdempotency`; a duplicate reconcile of the
   same `provider_ref` rolls back its tx (so the redundant `UpdatePaymentStatus` is undone
   too) → exactly one event, correct final status, a benign `Warn` log on the loser.

**Deployment context:** core-svc runs the reconciler as a *single* goroutine; the launch
deployment is a single VDS (one core-svc), so cron-overlap only arises under horizontal
scaling, where the outbox UNIQUE keeps state correct (cost: duplicate PSP `CheckStatus`
calls). **Not a bug; documented here so a future scale-out doesn't mistake it for one.**

## §2.4 Transactional shape (differs from the prompt's "SERIALIZABLE+retry" assumption)
`repo.WithTx` here is **plain `pool.Begin` at default isolation (ReadCommitted), no
40001 retry loop** — unlike the SERIALIZABLE+bounded-retry `WithTx(ctx, level, fn)` in
cashback/wallet/etc. This is appropriate: the reconciler's tx is a single-row status
update + a transactional-outbox insert — **not** a double-entry ledger move (those happen
downstream in the outbox event consumers). So the prompt's "mock 40001, assert bounded
SERIALIZABLE retry" cases are **N/A for this reconciler** (no retry loop exists to test).
Tx scope is **per-payment** (one `WithTx` per `reconcileOne`), not per-batch.

## §2.5 Dependencies surface (the test seam) — all constructor-injected interfaces
| Collaborator | Interface | Methods the reconciler uses |
|---|---|---|
| storage | `payment.Repository` | `FindExpiredPendingPayments`, `WithTx`, `UpdatePaymentStatus` |
| PSP | `payment.Service` | `CheckStatus` |
| events | `outbox.Repository` | `Insert` |
Plus scalars `market`, `currency`, `*slog.Logger`. **No hard-coded concrete deps** →
unit-testable with handwritten fakes; **no production TESTING-HOOK required.** (The only
wall-clock read is `time.Now().UTC()` for the `*_at` timestamp written via the fake/real
repo — assertable as "non-nil & recent" without a clock injection.)

## §2.6 State machine (per row, per pass)
```
pending(expired) --CheckStatus-->
   pending | unknown   -> (leave; re-evaluated next tick)
   captured           -> tx{ UpdatePaymentStatus(captured_at) + outbox(captured.v1) }
   failed             -> tx{ UpdatePaymentStatus(failed_at)   + outbox(failed.v1)   }
   refunded           -> tx{ UpdatePaymentStatus(refunded_at) + outbox(refunded.v1) }
```
There is no `claimed`/`in_progress`/`dead-lettered` persisted state — the prompt's richer
state machine does not exist here. Status is the only persisted lifecycle field.

## Test plan implications (what's testable vs N/A)
- **Unit (fakes):** queue selection, per-status branch (captured/failed/refunded/pending/
  unknown), exact idempotency key + event-type mapping, `market`/`currency` propagation,
  CheckStatus error → skip-and-continue, FindExpired error → pass error, UpdatePaymentStatus
  / outbox.Insert error → reconcileOne error (pass continues), `Run` honours ctx cancel,
  amount pass-through (incl. near `math.MaxInt64`), currency≠TRY.
- **Integration (real PG):** seed expired-pending rows → `runOnce` with a fake PSP →
  assert `status`/`*_at` updated + one outbox row; **atomicity** (outbox.Insert failure
  rolls back the status update); **concurrency** (two `runOnce` on the same row → exactly
  one outbox row via the UNIQUE key, correct final status).
- **N/A (documented, not fabricated):** lease expiration (no lease); worker-pool>1 as a
  *lease* test (covered instead by the outbox-idempotency concurrency case); SERIALIZABLE
  40001 retry (no retry loop); soft-deleted-user refusal (the reconciler never reads user
  state — it acts on `provider_ref`; user-state discipline lives in the downstream event
  consumers, not here).
