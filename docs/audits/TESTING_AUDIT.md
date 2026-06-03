# Testing Audit — 2026-06-03 — `chore/testing-audit` (Step 2 of the 5-step plan)

**Audit-only. No code fixed in this PR.** Findings are scoped into follow-up PRs (§8).

## TL;DR
- **CONFIRMED HIGH:  0**
- **CONFIRMED MED:   7** (original) — burn-down status: F-001 ✅ (PR #58); F-006 ✅, F-011 ✅ triaged, F-012 ✅ confirmed+fixed (this PR); F-002-treasury ⚠️ corrected-to-stub; F-002 (search/media/sizefinder) + payment.Service still open.
- **CONFIRMED LOW:   5** (weak determinism test; ungated staticcheck style; retry-without-backoff; legacy StateNotifiers; documented a11y FAIL)
- **PROBABLE:        3** (F-012 now CONFIRMED+FIXED; `context.Background()` in DLQ insert; Flutter rebuild storms)
- **UNKNOWN / not-run-this-pass: 3** (×50 `-race` repro; N+1 / `EXPLAIN ANALYZE`; Flutter DevTools rebuild counts)
- **NEW: F-016** (LOW, test-infra) — identity integration tests share one `integRedis`/`FlushDB` (order-fragile); surfaced triaging F-011; product verified correct.
- **Verified-not-actionable:** §3.1 concurrency, §3.2 tx-isolation/retry, §3.4 user-state-consumer, §4.2 Flutter dispose, §5.1 soft-refs.

**Honest headline:** post-cleanup (#54-#56) the codebase is healthy. There is **no confirmed correctness/financial/security defect**. The real signal is **test-coverage gaps** in a cluster of modules that escaped the property/integration nets (`payment`, `treasury`, `search`, `media`, `sizefinder`) — including a *live, wired* payment reconciler with zero tests — plus known tracked gaps (REVIVAL_GAP skips, identity-without-`-race`).

> **Layout note:** the Step-2 prompt used `services/*-svc/**` + `app/**`; this repo is `cmd/*-svc` + `internal/**` + `pkg/**` + `mobile/**` (module `github.com/mopro/platform`). All paths below are the real ones.

## Methodology (§2 discipline, carried from #54/#55/#56)
- **CONFIRMED** = reproduced on this branch (`main@5533ed8d`) with the command shown inline.
- **PROBABLE** = pattern visible, not reproduced. **UNKNOWN** = flagged, insufficient signal.
- **Build-tag awareness:** tags in repo are `integration`, `contract`, `sipay_sandbox`, `tools` (no `e2e` tag; the e2e suite uses `integration`). Absence-of-caller claims were re-checked across tags (the #54 `RefreshWorker`/`Sign*` lesson).
- **Design ≠ defect:** checked against CLAUDE.md locked designs + CONTRIBUTING before flagging.

---

## §3 Backend findings

### §3.1 Concurrency / races — VERIFIED-NOT-ACTIONABLE (with one carve-out → F-006)
```
$ go vet ./...                 → exit 0, clean
$ staticcheck ./... | grep -v U1000 | grep -v gen   → 7 style findings only (F-009), no SA-race
$ git grep -nE '\bgo func\(|type \w*Worker|\) Run\(ctx'  → 3 workers: outbox.Publisher, payment.Reconciler, wallet.RefreshWorker
```
`make verify` runs `integration-e2e` and `integration-cart` **with `-race`** (green as of PR #55). Pool-acquisition-inside-tx discipline was swept in PR #42/#47; no new violations. Worker shared-state: outbox/publisher and reconciler use request/loop-scoped ctx; no unguarded shared maps found. **Carve-out:** the identity suite is not `-race`'d (→ **F-006**), so identity concurrency (token rotation, family-revoke, rate-limiter) is unverified under the detector.

### F-001 — `internal/payment` package (incl. a live wired Reconciler) has zero tests
**Severity: MED | Confidence: CONFIRMED | ✅ RESOLVED-BY `test/payment-reconciler-coverage` (2026-06-03)**
> Resolved: added a white-box unit suite + a real-Postgres integration suite for
> `payment.Reconciler` (`internal/payment/reconciler_test.go`,
> `reconciler_integration_test.go`), gated by `make verify` via `integration-payment`
> (`-race`). Discovery doc: `docs/internal/payment-reconciler.md`. **Zero production-code
> changes** — the reconciler was already testable through its interface constructor. No new
> bug found: the "no lease" concurrency model is by-design (outbox `idempotency_key` UNIQUE
> backstop + `FOR UPDATE SKIP LOCKED` fetch), verified by the concurrency + atomicity tests.
> Scope note: `payment.Service` impls and the backup adapters (`craftgate`/`iyzico`) remain
> untested — out of this PR's scope (the *reconciler* was F-001's named risk); tracked under
> F-002's module-coverage follow-ups.
File: `internal/payment/*.go` (6 source files), `internal/payment/reconciler.go`
```
$ ls internal/payment/*_test.go            → no matches found
$ git grep -n 'NewReconciler' cmd/          → cmd/core-svc/main.go:265: paymentReconciler := payment.NewReconciler(
```
`payment.NewReconciler` is wired into core-svc at startup (a live background financial-reconciliation worker) yet `internal/payment` has **no co-located tests**. The PSP adapters split the picture: `internal/payment/sipay` *does* have `hmac_test.go` + `sipay_test.go` (integration); but the provider-agnostic `service.go`, adapter selection, and `reconciler.go` are untested. Backup adapters `craftgate`/`iyzico` also 0 tests (lower priority — sipay is the active PSP).
Impact: a financial worker's reconcile/transfer-orchestration logic can regress silently. Not a reproduced bug — a coverage risk on a money-adjacent path.
Recommendation: follow-up PR adds unit tests for `payment.Service` + `Reconciler` (table-driven over PSP-result shapes; fake adapter).

### F-002 — Service modules with zero co-located tests
**Severity: MED | Confidence: CONFIRMED | ⚠️ `treasury` slice CORRECTED + closed-as-not-actionable by `test/audit-burndown-identity-treasury` (2026-06-03)**
> **CORRECTION (the PR #57 lesson, again):** the audit counted `internal/treasury` as "5 src
> files" without reading them. It is a **12-LOC unimplemented stub** — `Service interface{}`,
> `Repository interface{}` (empty), empty `domain.go`/`errors.go`/`repository.go`/`service.go`,
> and **not wired into any binary**. There is no behaviour to test. F-002-treasury is closed as
> **not-actionable (stub)**, not via tests. The remaining F-002 modules (`search`, `media`,
> `sizefinder`) are still real coverage gaps — verify each is a real implementation (not a stub)
> before writing tests. (`payment.Service`/adapters folded in by PR #58 also remain.)
```
$ for d in $(find internal -type d); do src=$(ls $d/*.go 2>/dev/null|grep -vc _test.go); t=$(ls $d/*_test.go 2>/dev/null|wc -l); [ $src -gt 0 ] && [ $t -eq 0 ] && echo "$d ($src src,0 test)"; done
internal/treasury (5 src, 0 test)
internal/search   (5 src, 0 test)
internal/media    (5 src, 0 test)
internal/sizefinder (5 src, 0 test)
internal/ledger   (5 src, 0 test)   ← invariants covered indirectly, see note
```
`treasury` (float-yield, financial), `search` (Meilisearch), `media` (photo upload — also ops-blocked per project memory), `sizefinder` each have substantial source and no tests.
**Note on `internal/ledger`:** 0 co-located tests, **but** `make verify`'s `property-ledger` target runs `go test -run Property ./internal/wallet/...` — ledger double-entry invariants ARE property-tested *through wallet*. The shared ledger helper funcs lack *direct* unit tests (LOW), but the invariants are covered. Not a gap for correctness; a gap for helper-branch coverage.
Recommendation: per-module follow-up PRs (one each), starting with `treasury` (financial).

### F-003 — `wallet.RefreshWorker.Run`/`refresh` loop is untested
**Severity: LOW | Confidence: CONFIRMED**
File: `internal/wallet/refresh_worker.go:32,57`
```
$ git grep -ln 'RefreshWorker' -- '*_test.go'   → internal/wallet/wallet_integration_test.go
$ git grep -nE 'RefreshWorker.*\.Run\(' -- '*_test.go'   → (none)
$ make deadcode  → refresh_worker.go:32 RefreshWorker.Run, :57 refresh  (unreachable even w/ integration roots)
```
The integration test exercises `NewRefreshWorker(...).RefreshOnce(ctx)`; the `Run(ctx)` ticker-loop wrapper and its private `refresh` are never exercised (and `deadcode` flags them even with `-tags=integration`). The loop is thin (ticker → RefreshOnce), so risk is low, but the loop/shutdown path is uncovered.
Recommendation: a small test that runs `Run` with a short interval + cancellable ctx, asserting it ticks once and exits on ctx cancel.

### §3.2 Transaction isolation / SERIALIZABLE retry — VERIFIED-NOT-ACTIONABLE
```
$ git grep -nE 'BeginTx|TxIsoLevel|Serializable' internal/   → every module's WithTx takes an explicit pgx.TxIsoLevel
```
Financial paths pass `pgx.Serializable` (`cashback/run_month.go:161`, `orderledger/service.go:141`, `catalog/service.go:249`); non-financial read paths use `ReadCommitted` (`eventbus/dlq.go:128`, `reconcile/repository.go:29`) — appropriate. Retry is bounded:
```
$ sed -n '25,48p' internal/cashback/repository.go
  const maxRetries = 3 ; ... if isSerializationFailure(err) && attempt<maxRetries-1 { continue } ; ... return ErrMaxRetriesExceeded
```
Same shape in wallet/catalog/orderledger/sellerpayout. → **F-008 (LOW):** the retry `continue`s immediately with **no jitter/backoff** (thundering-herd risk under high contention; bound of 3 keeps it small).

### §3.3 Storage idempotency — VERIFIED-NOT-ACTIONABLE
```
$ git grep -nE 'ON CONFLICT|idempotency_key' internal/   → present across cashback (plan_id,period), payouts (payout_id), reviews, returns, q&a
$ git grep -n 'InsertPlanIfAbsent' internal/cashback/repository.go  → ON CONFLICT (order_id) idempotent re-delivery
```
The `Idempotency-Key` HTTP middleware (`internal/idempotency/middleware.go`) + storage-layer UNIQUE guards are in place; CLAUDE.md §4.4 mandate is honored. (One weak *test* of the key fn → F-007, not a code defect.)

### §3.4 User-state-consumer discipline — VERIFIED-NOT-ACTIONABLE
```
$ git grep -nc 'StatusDeleted' internal/identity/service.go   → 14 guard sites
```
PR #49 swept every consumer; 14 `StatusDeleted` guards remain in `service.go`. No new unguarded consumer found.

### §3.6 Error handling — no CONFIRMED findings this pass
`errcheck` is in the golangci gate (incl. `check-type-assertions: true`), so dropped errors fail CI. `context.Background()` uses (§3.1 grep) are cleanup/durability paths → see F-010 (PROBABLE).

### §3.7 Coverage matrix (high-signal gaps; full per-symbol matrix deferred to fix PRs)
| Module | src files | co-located tests | covered indirectly? | gap |
|---|---|---|---|---|
| `internal/payment` (+reconciler) | 6 | 0 (sipay subpkg has tests) | partially (sipay hmac/integration) | **MED (F-001)** |
| `internal/treasury` | 5 (but **12 LOC empty stub**) | 0 | n/a | ⚠️ CORRECTED — unimplemented stub, not-actionable |
| `internal/search` | 5 | 0 | no | MED (F-002) |
| `internal/media` | 5 | 0 | no | MED (F-002) |
| `internal/sizefinder` | 5 | 0 | no | MED (F-002) |
| `internal/ledger` | 5 | 0 | yes (property-ledger via wallet) | LOW (F-002 note) |
| `internal/identity/{jwt,ratelimit,middleware}` | 1-2 each | 0 | yes (identity integration/property) | LOW |
| `internal/payment/{craftgate,iyzico}` | 1 each | 0 | no (backup adapters) | LOW |

### §3.8 Migration safety — UNKNOWN (not deeply audited this pass)
Not reproduced this pass; `migrations/**` reversibility + lock-duration review flagged for a focused follow-up (needs per-migration reading + `EXPLAIN`). UNKNOWN-pending.

---

## §4 Frontend findings

### §4.1 Riverpod Notifier shapes — F-004
**Severity: LOW | Confidence: CONFIRMED**
```
$ rg -l 'StateNotifier' mobile/lib -g '*.dart'
mobile/lib/design/theme_controller.dart
mobile/lib/features/favorites/favorites_provider.dart
mobile/lib/features/cart/application/guest_cart_provider.dart
mobile/lib/features/catalog/providers/recent_searches_provider.dart
```
4 files use legacy `StateNotifier` (CLAUDE.md documents the modern `Notifier`/`AsyncNotifier` shapes). These work; flagged as migration candidates, not defects. The post-await-mutation / `mounted`-recheck audit of each `AsyncNotifier` is deferred to a focused follow-up (needs per-notifier reading).

### §4.2 Widget lifecycle / dispose — VERIFIED-NOT-ACTIONABLE
```
$ for f in $(rg -l 'TextEditingController|AnimationController|ScrollController|PageController' mobile/lib -g '*.dart'); do rg -q 'void dispose\(\)' $f || echo $f; done
(no output)
```
Every widget holding a controller defines `dispose()`. No leak candidates found.

### §4.3 Build storms — UNKNOWN (needs DevTools)
`flutter analyze` is clean under strict `very_good_analysis`. Rebuild-scope problems can't be confirmed statically; flagged PROBABLE/UNKNOWN for a DevTools rebuild-counter pass.

### §4.5 Flutter test coverage — covered by `flutter-ci.yml`
The full widget+golden suite runs in `flutter-ci.yml` per-PR (not in `make verify` — see F-005). Per-screen golden gap analysis deferred (no regen per scope).

---

## §5 Cross-cutting findings

### §5.1 Cross-schema soft refs — VERIFIED-NOT-ACTIONABLE (documented design)
CLAUDE.md §5: cross-schema refs are BIGINT with no FK by design; the user-state-deleted check (§3.4) is the consumer-side guard and is present (PR #49). Not a defect.

### §5.2 Idempotency surface — covered (see §3.3); no "none" endpoints found in mutation handlers spot-check.

### F-010 — `context.Background()` in DLQ attempt-insert (durability path)
**Severity: LOW | Confidence: PROBABLE**
File: `internal/eventbus/redis_bus.go:633,641`; also `idempotency/middleware.go:57` (lock release), `outbox/publisher.go:159` (graceful drain).
```
$ git grep -nE 'context\.Background\(\)' internal/ | grep -v _test
```
These detach from the request ctx deliberately (record the attempt / release the lock / drain on shutdown *even if* the caller ctx is cancelled). Likely intentional, but the DLQ inserts have no timeout — a hung DB could block the consumer. PROBABLE-LOW; recommend `WithTimeout` rather than bare `Background()`.

---

## §6 Test-infrastructure findings

### F-005 — `make verify` runs only ONE Flutter test locally
**Severity: LOW | Confidence: CONFIRMED**
```
$ grep verify-contrast Makefile → cd mobile && flutter test test/design/contrast_test.dart
```
`make verify`'s Flutter step is just the WCAG contrast test; the full widget+golden suite is **not** in `make verify`. It IS gated per-PR by `flutter-ci.yml` (so CI catches breaks), but a dev running `make verify` locally won't catch a Flutter widget-test regression. LOW (CI covers it; local/CI parity gap only).

### F-006 — identity integration suite runs without `-race`
**Severity: MED | Confidence: CONFIRMED | ✅ RESOLVED-BY `test/audit-burndown-identity-treasury` (2026-06-03)**
> Added `make integration-identity-race`: `go test -race -skip 'OTPCodeDistribution'
> ./internal/identity/...` (the targeted run the recommendation called for — excludes the
> one bcrypt-heavy test that blows the CI budget under `-race`). Wired into `make verify`.
> **Result: clean — zero races over `-count=3` (~26s/run).** The identity concurrency code
> (refresh rotation, family-revoke, OTP rate-limiter, step-up) was race-safe; it had simply
> never been checked. No new race findings.
```
$ sed -n '415,419p' Makefile
integration-identity: ... go test -tags=integration ./internal/identity/... -count=1 -timeout 5m   # NO -race
```
`integration-cart` and `integration-e2e` run with `-race`; `integration-identity` does not (documented reason, PR #48: `OTPCodeDistribution`'s 600 bcrypt calls are too slow under `-race` on the 2-vCPU CI runner). Consequence: identity concurrency (refresh-token rotation, family-revoke theft detection, OTP rate-limiter) **never executes under the race detector** anywhere — no nightly `-race` job exists either.
Recommendation: a targeted `-race` run of identity's concurrency tests *excluding* the bcrypt distribution test (own target or nightly workflow).

### F-007 — near-tautological determinism property test
**Severity: LOW | Confidence: CONFIRMED**
File: `internal/idempotency/property_test.go:28`
```
$ staticcheck ./internal/idempotency/...
property_test.go:28:11: identical expressions on the left and right side of the '==' operator (SA4000)
  return idempotency.Key(userID, idemKey) == idempotency.Key(userID, idemKey)
```
`f(x) == f(x)` passes for any pure function; it only catches internal non-determinism (randomness/time) and gives near-zero signal for a hash fn. Recommend asserting against a fixed expected value (golden) for true determinism coverage.

### F-009 — ungated staticcheck style findings
**Severity: LOW | Confidence: CONFIRMED**
7 non-generated: `S1016` ×5 (use struct conversion not literal — `cashback/consumer.go:86`, `orderledger/consumer.go:65`, `sellerpayout/{consumer,fraud_event_handler,psp_event_handler}.go`), `ST1011` (`eventbus/redis_bus.go:36` unit-suffix var name). Not in the golangci enabled set, so ungated. Cosmetic; optional `staticcheck` addition to the gate is a judgment call (it also flags generated code — would need `gen/` excludes).

### F-011 — five REVIVAL_GAP tests skipped
**Severity: MED | Confidence: CONFIRMED | ✅ TRIAGED-BY `test/audit-burndown-identity-treasury` (2026-06-03)**
> Per-test triage (ran each with overrides + in full-suite context):
> | Test | Decision | Why |
> |---|---|---|
> | `Service_OTPVerifyFlow` | **RESTORED** | passes now F-012's jti fix makes rotated tokens distinct |
> | `LogoutRevokesToken` | **RESTORED** | behaviour correct; assertion broadened to accept `ErrTokenFamilyRevoked` (the revoke-on-logout outcome) |
> | `StepUpOTPFlow` | **RESTORED** | stale step-3 dropped — `FindLatestOTP` filters `verified_at IS NULL`, so a consumed login OTP is correctly excluded (one-time use) |
> | `RateLimiter_OTPRequest_PhoneWindow` | **→ F-016** | limiter is correct (passes isolated; Lua `count>=max`); fails only in the shared-`integRedis` suite. Test-infra, not a product bug. Left skipped pointing at F-016 |
> | `DLQContainsExactlyPermanentFailures` | **DOCUMENTED** | reclassified REVIVAL_GAP→FLAKY_SKIP (timing-flaky by design; deterministic siblings cover the paths) |
> 3 restored+passing, 1 new finding, 1 documented. No silent leaves.

### F-016 — identity integration tests share one `integRedis` + per-test `FlushDB` (order-fragile)
**Severity: LOW (test-infra) | Confidence: CONFIRMED | NEW (surfaced triaging F-011)**
```
$ go test -run '^TestInteg_RateLimiter_OTPRequest_PhoneWindow$' ./internal/identity/   → PASS (isolated)
$ go test -run 'RateLimiter|LogoutRevokes|OTPVerify|StepUp' ./internal/identity/        → RateLimiter FAILs (nil on 4th)
$ grep -c integRedis.FlushDB internal/identity/integration_test.go                       → 7
```
7 identity tests share the package-global `integRedis` client and each `FlushDB`s at start.
The sliding-window rate-limiter test asserts an empty window, but a sibling's `FlushDB` can
clear its zset within the same `go test` run → false "4th not limited". **The product
(limiter) is correct** (isolated pass + Lua `count>=max` proof). Fix is test-infra: give
each test an isolated key namespace or its own Redis DB index, then un-skip the rate-limiter
test. Not fixed here (F-011 was triage, not test-harness rework).
```
$ git grep -nE 'REVIVAL_GAP|skipRevivalGap' -- '*.go'
internal/e2e/dlq_e2e_test.go:325                 (flaky DLQ-membership; E2E_RUN_FLAKY_DLQ=1)
internal/identity/e2e_test.go:212                LogoutRevokesToken
internal/identity/integration_test.go:486        RateLimiter_OTPRequest_PhoneWindow
internal/identity/integration_test.go:556        Service_OTPVerifyFlow   ← see F-012
internal/identity/integration_test.go:683        Integration_StepUpOTPFlow
```
Five tests are skip-guarded (run only with env overrides). Each is either a stale assertion or a real regression — unreconciled. Tracked in Backlog but not closed. The DLQ one is a known flaky-under-gate property test (aggressive autoclaim).
Recommendation: reconcile one-by-one in a focused PR (stale → update assertion; real → file as its own bug).

### F-012 — JWT same-second token collision (no jti)
**Severity: MED | Confidence: CONFIRMED → ✅ CONFIRMED-AND-FIXED-BY `test/audit-burndown-identity-treasury` (2026-06-03)**
> **CONFIRMED:** `issue()` set only `Subject`/`IssuedAt`(1s-resolution)/`ExpiresAt` + `uid`/
> `mkt`/`scope`, **no `jti`** → two same-second access (and step-up) tokens were byte-identical.
> Probe `TestIssueAccess_SameSecond_DistinctJTI` (and step-up sibling) reproduced it.
> **Severity corrected PROBABLE-HIGH → CONFIRMED-MED:** access tokens are stateless bearer
> JWTs (two identical same-second tokens grant identical access — no boundary crossed);
> rotation security lives in the separate opaque refresh tokens. The jti's value is hygiene +
> enabling a future per-token denylist (PR #49 backlog).
> **FIXED (trivial, §4.2.3):** `RegisteredClaims.ID = uuid.NewString()` (uuid already a dep) —
> additive, `Verify` ignores it, nothing keys on the token string, refresh tokens independent.
> Probe green at HEAD; unblocked F-011's `Service_OTPVerifyFlow`.

(original PROBABLE write-up:)
File: `internal/identity/integration_test.go:556`
The `Service_OTPVerifyFlow` REVIVAL_GAP reason: *"access token not different after rotation (likely JWT same-second collision)."* If two access tokens issued within the same second are byte-identical (iat-only entropy, no jti/nonce), refresh-rotation produces a token indistinguishable from its predecessor — which weakens rotation/replay semantics. Not reproduced this pass (test is skipped). PROBABLE-MED; the follow-up that reconciles F-011 should determine whether this is a stale test or a real token-entropy bug (check whether `IssueAccess` includes a unique `jti`).

### §6.3 Reproducibility (×50 `-race`) — UNKNOWN / not-run-this-pass
The existing `-race` integration gate (e2e/cart) is green (PR #55). A dedicated ×50 `-race` stress of the three most complex storage tests was **not run this pass** (cost/time); flagged for a follow-up race-hardening pass. Honest UNKNOWN, not a clean bill.

### §3.5 N+1 / `EXPLAIN ANALYZE` — UNKNOWN / not-run-this-pass
Query profiling needs a seeded DB + access patterns; not done this pass. Flag for a dedicated perf follow-up.

---

## §7 Verified-not-actionable (commands shown above)
- **§3.1** concurrency (go vet clean; `-race` e2e/cart green; pool discipline swept; no unguarded worker state) — *except* F-006.
- **§3.2** tx isolation + bounded SERIALIZABLE retry (explicit per module).
- **§3.3** storage idempotency (middleware + UNIQUE/ON CONFLICT guards).
- **§3.4** user-state-consumer (14 guards; PR #49).
- **§4.2** Flutter dispose (no controller leaks).
- **§5.1** cross-schema soft-refs (documented design).

## §8 Recommended follow-up PR sequence (each <500 LOC, by severity)
1. **`test/payment-reconciler-coverage`** (F-001) — unit tests for `payment.Service` + `Reconciler` (fake adapter). *Highest value: live financial worker.*
2. **`test/identity-race-target`** (F-006) — add a `-race` identity target excluding `OTPCodeDistribution`; wire as nightly or its own PR job.
3. **`test/revival-gap-reconcile`** (F-011 + F-012) — reconcile the 5 skips; determine if F-012 is a real jti/entropy bug (if so, split into a fix PR).
4. **`test/module-coverage-treasury`** then `search` / `media` / `sizefinder` (F-002) — one module per PR; treasury first (financial).
5. **`test/wallet-refresh-loop` + `chore/idempotency-determinism-test`** (F-003, F-007) — small.
6. **`chore/retry-backoff` + `chore/dlq-ctx-timeout`** (F-008, F-010) — small quality.
7. **`chore/flutter-statenotifier-migration`** (F-004) — legacy → Notifier, per file.
8. Deferred passes: migration-safety audit (§3.8), N+1/EXPLAIN (§3.5), ×50 `-race` repro (§6.3), Flutter rebuild-storm DevTools pass (§4.3).

Fix PRs MUST reference the finding ID (e.g. "closes TESTING_AUDIT F-001").
