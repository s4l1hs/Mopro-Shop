# Testing Audit — 2026-06-03 — `chore/testing-audit` (Step 2 of the 5-step plan)

**Audit-only. No code fixed in this PR.** Findings are scoped into follow-up PRs (§8).

## TL;DR

> ## ✅ STEP 2 CLOSED — `test/step2-closure-wallet-gate-f003-f017` (2026-06-03)
> Final three items resolved: **wallet-integration gate** added + canary-proven (closes PR #60's
> ungated-suite observation); **F-003** RESOLVED (RefreshWorker.Run unit+integration tests);
> **F-017** RESOLVED (unique zset member → limiter enforces same-ms bursts; F-016 test unskipped).
> Every audit finding F-001→F-017 now has a terminal outcome (RESOLVED / NOT-ACTIONABLE /
> CORRECTED). The audit-then-fix arc (#57→#58→#59→#60→this) is structurally complete.
>
> **Post-Step-2 addendum (2026-06-06):** wiring the Trendyol-parity post-audit tail surfaced
> **F-018** (integration suites that run in no CI gate) — analytics + shipping wired; 10 more carved.
> See F-018 below + `docs/internal/integration-tests-wiring.md`.

- **CONFIRMED HIGH:  0**
- **CONFIRMED MED:   7** (original) — F-001 ✅ (#58); F-006/F-011/F-012 ✅ (#59); **F-002 ✅ PARTIAL** (4 of 5 "modules" are 12-LOC stubs → not-actionable; payment.Service REAL → sliced this PR).
- **CONFIRMED LOW:   5** — **F-007 ✅ FIXED** (#60); **F-008 / F-010 / F-004 ✅ NOT-ACTIONABLE** (#60); **F-003 ✅ RESOLVED** (closure PR — wallet gate unblocked it); documented a11y FAIL stands.
- **PROBABLE:        3** (`context.Background()` DLQ → NOT-ACTIONABLE; Flutter rebuild storms; F-012 confirmed+fixed in #59)
- **UNKNOWN / not-run-this-pass: 3** (×50 `-race` repro; N+1 / `EXPLAIN ANALYZE`; Flutter DevTools rebuild counts) — deferred, not part of Step 2's fix sequence.
- **F-016** ⚠️ CORRECTED (#60) → **F-017 ✅ RESOLVED** (closure PR): unique zset member per request; limiter now enforces same-ms bursts; F-016 test unskipped + green in the full suite.
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
**⚠️ RE-AUDIT (real-vs-stub) — `test/audit-burndown-f002-f016-low` (2026-06-03):** the "5 src, 0 test" count was file-presence, not code (the treasury/PR #57 mistake, repeated). Reading every file:

| Module | LOC | Real logic? | Status |
|---|---|---|---|
| `internal/treasury` | 12 | no (empty interfaces) | **STUB** (confirmed PR #59) |
| `internal/search` | 12 | no (`Service interface{}` / `Repository interface{}`) | **STUB** |
| `internal/media` | 12 | no (empty interfaces) | **STUB** |
| `internal/sizefinder` | 12 | no (empty interfaces) | **STUB** |
| `internal/payment` (`service.go`) | 91 | **yes** — PSP provider registry/factory dispatch + craftgate/iyzico stubs | **REAL** |

So **4 of the 5 "modules" are 12-LOC stubs** — nothing to test (closed NOT-ACTIONABLE). The only REAL one is `payment.Service` (provider registry/factory), the smallest real F-002 surface → **sliced this PR** (unit tests, no DB). `internal/ledger` invariants are covered indirectly (`property-ledger` runs `go test -run Property ./internal/wallet/...`); helper-branch coverage is the only residual (LOW). **F-002 net: PARTIAL-RESOLVED — payment.Service sliced; the 4 stubs are not-actionable (they need implementation, not tests).**

### F-003 — `wallet.RefreshWorker.Run`/`refresh` loop is untested
**Severity: LOW | Confidence: CONFIRMED | ✅ RESOLVED-BY `test/step2-closure-wallet-gate-f003-f017` (2026-06-03)** (was DEFERRED in #60)
> The blocker (no wallet-integration gate) is gone — this PR added `integration-wallet`
> (Step 2 wallet-gate, canary-proven). Then added: a no-DB unit test (Run exits on ctx
> cancel) + integration tests (Run loop refreshes the MV; Run survives refresh errors on a
> closed pool without panicking). Discovery: `docs/internal/wallet-refresh-worker.md`.
> `-race` clean, loop test stable ×3. (Also surfaced + handled: `Run` panics on a nil logger —
> `NewRefreshWorker` defaults the interval but not the log; tests pass `slog.Default()`. Not a
> production change; noted as a minor constructor-robustness footgun.)
> Deferred (real, but the proper fix exceeds LOW scope). The non-Property wallet integration
> tests aren't in `make verify` — `property-ledger` runs only `go test -run Property
> ./internal/wallet/...`, so `TestIntegration_*` (incl. the existing `RefreshOnce` coverage)
> is **ungated**. A `RefreshWorker.Run` loop test would also be ungated; making it valuable
> needs a gated wallet-integration target first (mirror `integration-payment`), which gates the
> whole currently-ungated wallet integration suite at once (could surface latent failures) —
> its own small infra PR, not a LOW drive-by. (Observation: ungated wallet integration suite is
> itself worth a follow-up.)
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
Same shape in wallet/catalog/orderledger/sellerpayout. → **F-008 (LOW): ✅ NOT-ACTIONABLE-BY `test/audit-burndown-f002-f016-low` (2026-06-03)** — the retry `continue`s immediately with no jitter/backoff, but it is **bounded (3 attempts)** and SERIALIZABLE conflicts are rare + short-lived, so immediate retry is an acceptable design (not a defect). Adding backoff to 6 financial modules' tx paths is a cross-cutting optimization disproportionate to a LOW drive-by and warrants a deliberate, separately-tested change if ever wanted. Closed not-actionable.

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
**✅ NOT-ACTIONABLE-BY `test/audit-burndown-f002-f016-low` (2026-06-03)** — `StateNotifier` is a
valid (if older) Riverpod pattern, not a defect; "migration to `Notifier`" is a preference, and
**Flutter is out of scope** for the backend-focused burn-down PRs. Not actionable here; if a
Flutter modernization pass happens (Step 3-ish), it can revisit. The 4 files still work.
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
**Severity: LOW | Confidence: PROBABLE | ✅ NOT-ACTIONABLE-BY `test/audit-burndown-f002-f016-low` (2026-06-03)**
> Re-read in context (`internal/eventbus/redis_bus.go` ~628-642): the `context.Background()`
> uses are the **drain-on-shutdown** path (`ctx.Done()` → drain remaining attempt-log rows) and
> a decoupled fire-and-forget durability writer — both deliberately detach from the (cancelled)
> request ctx and log-and-continue on error. Using the live ctx there would drop attempt logs on
> shutdown. Not a defect; intentional. A per-call timeout would be marginal background hardening,
> not a fix. Closed not-actionable.
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
**✅ RESOLVED — `make integration-identity-race` (F-006) + the chi-square removal (`fix/otp-distribution-flake`).** The targeted `-race` target now runs the **whole** identity integration suite under the detector (no exclusion): the slow `OTPCodeDistribution` chi-square test was a statistical test of `crypto/rand.Int`'s uniformity (not Mopro's logic) — it false-failed at its alpha rate by definition and was the only `-race`-excluded test — so it was replaced by a deterministic `TestOTPCode_Format` (whitebox) and its redundant integration copy deleted. `make soak` also dropped the `-skip`. (closes flake `TestProperty_OTPCodeDistribution`.)

### F-007 — near-tautological determinism property test
**Severity: LOW | Confidence: CONFIRMED | ✅ RESOLVED-BY `test/audit-burndown-f002-f016-low` (2026-06-03)**
> Fixed: `TestProperty_Key_Deterministic` now asserts `Key(userID,k) == fmt.Sprintf("idem:%d:%s",…)`
> instead of `Key(x)==Key(x)`. Real determinism + format coverage; staticcheck SA4000 cleared.
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

### F-016 — identity rate-limiter test fragility — ⚠️ CORRECTED → real cause is F-017
**Severity: LOW (test-infra) | ❌ HYPOTHESIS REFUTED by `test/audit-burndown-f002-f016-low` (2026-06-03)**
> PR #59's "shared-`integRedis` / `FlushDB` ordering" hypothesis was **WRONG**: the identity
> tests are **sequential** (no `t.Parallel` anywhere), so a sibling's `FlushDB` cannot race the
> rate-limiter test. Re-investigation (running `TestInteg_RateLimiter*` as a group → PhoneWindow
> fails first, solo → passes) pointed at **timing**, and reading the Lua nailed it:
> `slidingWindowLua` does `ZADD key now now` — the **millisecond timestamp is the zset MEMBER**,
> so multiple `CheckOTPRequest` calls in the same millisecond collide to one member, `ZCARD`
> undercounts, and the limit isn't enforced. Solo runs are slower (distinct ms → pass); grouped
> runs are faster (same ms → undercount → 4th wrongly allowed). **This is a real (LOW) product
> robustness gap, not a test-infra one.** F-016 closed as CORRECTED; product cause filed as F-017.

### F-017 — sliding-window rate-limiter uses ms timestamp as zset member (same-ms undercount)
**Severity: LOW | Confidence: CONFIRMED | ✅ RESOLVED-BY `test/step2-closure-wallet-gate-f003-f017` (2026-06-03)**
> Fixed: the Lua now takes a unique member per request (`<nowMS>:<uuid>`, ARGV[4]) instead of
> `ZADD key now now`; the score stays nowMS so window-trimming is unchanged, and ZCARD now
> equals the real request count. Impact pre-fix: a same-millisecond burst collapsed to one
> zset element, so the per-window cap (phone 3/10min, 5/1hr; IP 10/1hr) was bypassable by a
> scripted attacker firing requests in <1ms (ordinary network-spaced traffic was unaffected).
> Burst tests (`limiter_burst_test.go`, `-race`): same-ms burst of 10 → exactly 3 allowed;
> concurrent burst of 12 → exactly 3; under-limit all pass. The F-016 test
> (`TestInteg_RateLimiter_OTPRequest_PhoneWindow`) is **unskipped** and passes in the full
> identity suite (stable ×5) — confirming F-017, not the refuted F-016 test-infra hypothesis,
> was the true cause. **F-016 fully closed.**
File: `internal/identity/ratelimit/limiter.go` (`slidingWindowLua`, ~line 51)
```
local now = tonumber(ARGV[3])     -- UnixMilli
...
redis.call('ZADD', key, now, now) -- score AND member = now (ms)
```
Because the member is the ms timestamp, ≥2 requests in the same millisecond are stored as ONE
zset element → `ZCARD` < actual request count → the per-window limit (e.g. phone 3/10min) is
under-enforced under a same-ms burst (a scripted OTP-spam attacker could partially bypass it;
ordinary network-spaced requests are unaffected). **Fix = unique member per request** (e.g.
`now .. ':' .. <counter|uuid>` as the member, keeping `now` as the score). Deferred (security-
adjacent product code; own focused PR with burst tests). The rate-limiter test stays skipped
pointing at F-017 (it's actually a *correct* assertion exposing this gap).
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

### F-018 — integration suites that run in no CI gate (post-Step-2 addendum, 2026-06-06)
**Severity: MED | Confidence: CONFIRMED | ⏳ PARTIAL — analytics + shipping RESOLVED-BY `chore/wire-post-audit-integration-tests`; 10 suites carved**
> Surfaced while wiring the post-audit tail (analytics #100 + delivery-ETA #97). `make verify` is the
> **only** CI path that runs `-tags=integration` (make-verify.yml); openapi-ci runs `go test -race ./...`
> with **no** integration tag, so any `//go:build integration` suite not chained in `verify` runs nowhere.
> **Closed here:** `integration-analytics` (suite self-bootstraps `analytics_schema`; reuses pg-ecom-e2e)
> + `integration-shipping` (new LookupTransit + 0085-seed test). **Still open (carved):** 10 suites —
> `test-integration-{order,sellerpayout,outbox}` exist but **bind the same ports the e2e-cluster uses**
> (:6435/:6434/:6380), so appending them to `verify` collides; they need the cart/identity-style
> container-**reuse** rework. Plus `api`(fin), `attachments`, `help`, `idempotency`, `inbox`, `reconcile`,
> `seller` have **no target** (each needs per-package triage: which DB/schema, self-bootstrap vs migration,
> green-or-rotted). Per-package map: `docs/internal/integration-tests-wiring.md` §2/§4.
Recommendation: a `chore/revive-unwired-integration-suites` follow-up, reviving each into the e2e-cluster
reuse pattern (precedent: `chore/revive-cart-identity-integration-tests`), one cluster per commit — **not**
a blanket add (a rotted suite would turn `verify` red). Fix PRs reference "closes TESTING_AUDIT F-018".

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
2. ✅ **`test/identity-race-target`** (F-006) — DONE: `make integration-identity-race` + nightly `make soak`. The `OTPCodeDistribution` exclusion is gone (`fix/otp-distribution-flake` replaced that chi-square with a deterministic format test), so the target now runs the whole identity suite under `-race`.
3. **`test/revival-gap-reconcile`** (F-011 + F-012) — reconcile the 5 skips; determine if F-012 is a real jti/entropy bug (if so, split into a fix PR).
4. **`test/module-coverage-treasury`** then `search` / `media` / `sizefinder` (F-002) — one module per PR; treasury first (financial).
5. **`test/wallet-refresh-loop` + `chore/idempotency-determinism-test`** (F-003, F-007) — small.
6. **`chore/retry-backoff` + `chore/dlq-ctx-timeout`** (F-008, F-010) — small quality.
7. **`chore/flutter-statenotifier-migration`** (F-004) — legacy → Notifier, per file.
8. Deferred passes: migration-safety audit (§3.8), N+1/EXPLAIN (§3.5), ×50 `-race` repro (§6.3), Flutter rebuild-storm DevTools pass (§4.3).
9. **`chore/revive-unwired-integration-suites`** (F-018) — revive the 10 carved suites into the e2e-cluster reuse pattern, one cluster per commit. `analytics` + `shipping` already done in `chore/wire-post-audit-integration-tests`.

Fix PRs MUST reference the finding ID (e.g. "closes TESTING_AUDIT F-001").
