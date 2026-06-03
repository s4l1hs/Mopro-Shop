# Architecture Audit — 2026-06-03 — Step 4 of the 5-step plan

**Audit-only. No code changes in this PR.** Findings are scoped into follow-up refactor PRs (§6).

> **BUILD PROGRESS:**
> - ✅ **A-001** (A4-1 `feat/payment-gateway-inject`) — `payment.Service` testable (injected provider
>   + `paymenttest.Fake`); discovery-shift: interface already existed, no `payment.Gateway` added.
>   **T-016 mock-PSP part resolved** (fin-svc harness remains).
> - ✅ **A-002 + A-006** (A4-2/A4-4 docs bundle) — CLAUDE.md reconciled (Built-vs-Planned); the 7
>   financial conventions consolidated in `docs/internal/financial-core.md`.
> - ✅ **A-003** (A4-3 `refactor/config-injection`) — sipay/storage/shipping/identity migrated to
>   injected config; eventbus reclassified intentional (ADR-0003). Cleared the A4-1-deferred sipay `GO_ENV`.
> - **STEP 4 CLOSED.** All findings resolved (A-001/002/003/006) or PROBABLE/PARK (A-004/A-007/A-005).
>   Step-4-adjacent open items live in the ROADMAP: idempotency-surface analyzer; cron-sim; the PR #74 flake.

## TL;DR
- **CONFIRMED HIGH:** 1 (A-001 = T-016, payment test-mode abstraction)
- **CONFIRMED MED:** 3 (A-002 constitution drift, A-003 config injection, A-006 financial-core docs)
- **CONFIRMED LOW:** 1 (A-005 Flutter feature layering)
- **PROBABLE:** 2 (A-004 shipping carrier test-mode, A-007 per-handler auth-coverage sweep)
- **UNKNOWN:** 0
- **VERIFIED-COMPLETE:** §3.1 service boundaries, §3.3 layer discipline (core), §3.5 API surface,
  §3.6 cross-service comms, §4.1 gated-rule drift, storage abstraction, ADR practice, Riverpod topology.
- **Recommended NOW:** **A-001** (payment mock adapter — unblocks T-016/cron-sim/fin-svc tests),
  **A-002** (reconcile CLAUDE.md with reality — cheap, high onboarding value).

**Honest headline:** after 19 PRs of disciplined cleanup/testing/tooling, the architecture is
**structurally clean** — and much of it is now *gated* (the module-boundary script, depguard, the
lint-discipline analyzers, the Riverpod detector), so "is X respected?" is answerable by a green
gate rather than archaeology. The genuine gaps cluster narrowly: **one missing abstraction**
(a test/mock PSP adapter — the long-standing T-016, which also explains why `payment/service.go`
reads env directly), and **documentation drift** (CLAUDE.md, the "constitution," describes a v7
module set that isn't all built). Everything the prior arc gated shows **zero drift**.

> **Layout note:** the prompt's `services/**` paths are this repo's `cmd/<svc>/main.go` (3 binaries:
> core-svc, fin-svc, jobs-svc) wiring disjoint `internal/<module>` sets, shared `pkg/`. The "service
> boundary" is the module→binary mapping enforced by `scripts/check-module-boundaries.sh`.

## Methodology (§2 discipline, carried from #57–#72)
- **CONFIRMED** = reproduced on this branch (`main@793519db`) with the inline command shown.
- **PROBABLE** = structure suggests it, import-graph not fully traced. **UNKNOWN** = insufficient signal.
- **Shape** per finding: BOUNDARY-VIOLATION / MISSING-ABSTRACTION / TANGLED / LEAKY / DUPLICATED / UNDOCUMENTED.
- §2.2: documented/LOCKED designs are not violations — checked CLAUDE.md, CONTRIBUTING, ADRs, the
  REPORT before flagging (it changed two would-be findings to "intentional", below).
- §2.3: architecture intuition is recall-prone — boundary/tangle/abstraction findings are traced
  with `go list -deps` / `git grep`, and a MISSING-ABSTRACTION is only CONFIRMED if a useful test
  would exist against the proposed interface (A-001 passes that bar; A-004 is left PROBABLE).

---

## §3.1 Service-level boundaries — VERIFIED-COMPLETE
The 3 binaries wire disjoint module sets; cross-binary leakage is gated by
`scripts/check-module-boundaries.sh` (144 lines) + depguard, and confirmed by the import graph:
```
$ go list -deps ./cmd/fin-svc/...  | grep -E 'internal/(identity|catalog|cart|order|seller|search)$'   → (none)
$ go list -deps ./cmd/core-svc/... | grep -E 'internal/(wallet|cashback|sellerpayout|commission|treasury)$' → (none)
```
core-svc ↔ fin-svc carry **no** direct module dependency in either direction (they communicate via
Redis Streams events + the outbox, per CLAUDE.md §3.2). No cross-service DB access, no service
importing another's internals, no circular service deps. **No findings.**

---

## §3.2 Within-service module boundaries — mostly clean
32 `internal/` modules; the boundary script forbids cross-module `*/repository` imports and depguard
enforces it at lint time. No "god module" import hub found. One PROBABLE coupling note folded into
A-006 (the financial core — ledger/outbox/eventbus/orderledger — is intricate but correctly layered;
its issue is *documentation*, not coupling). **No boundary findings.**

---

## §3.3 Layer discipline — VERIFIED-COMPLETE (with one documented exception)
```
$ git grep -nE 'http\.(ResponseWriter|Request)|gin\.' -- 'internal/*/api.go'   → (none)
$ git grep -nE 'pgx\.|pgxpool\.' -- 'internal/*/api.go'                         → pgx.Tx in attachments, cashback
```
No HTTP transport types leak into `api.go` `Service` interfaces (handlers→service→repo holds).
`pgx.Tx` **does** appear in some `Repository` interfaces (`cashback.PostInTx`, `attachments.AttachInTx`)
— but this is the **documented in-tx coordination exception** (CLAUDE.md §3.1/§5 + CONTRIBUTING's
two-phase-commit pattern; the cashback `api.go` even pins the isolation level by comment). `pgx.Tx`
is itself an interface and PostgreSQL/pgx is a LOCKED tech choice (CLAUDE.md §8), so this is
intentional, not a leaky abstraction. **Not a finding** (§2.2).

---

## §3.4 Cross-cutting concerns
- **Auth:** centralized in `internal/identity/middleware/{auth,seller}.go`, applied in core-svc
  handlers — not scattered. Good. (Per-handler *coverage* is A-007, PROBABLE.)
- **Logging / metrics / tracing:** centralized in `pkg/logx`, `pkg/metrics`, `pkg/otelx` — shared,
  injected. No `log.Printf` scatter pattern found in handlers. Good.
- **Idempotency:** the storage-layer pattern is gated (the migration-safety + lint-discipline arc);
  34 `ON CONFLICT` usages; the idempotency-surface analyzer (Step-3 split) will complete the gate.

### A-003 — config read directly in internal modules (no central loader)
**✅ RESOLVED (A4-3) — was MED/SOON.** Re-verified post-A4-1: of the audit's 7, payment was
already done (#74), and **eventbus is intentional** (ADR-0003 per-stream MAXLEN tuning overrides
with defaults — §2.2, not a violation). The 4 real reads migrated to injected config:
**sipay** (`SipayConfig.Environment` — clears the A4-1-deferred `GO_ENV` invariant), **storage**
(`storage.Config`), **shipping** (`inProduction bool`), **identity** (`WithDevOTPBypass` functional
option — zero test-caller cascade on the auth core). Each prod-safety guard preserved exactly
(typed error / panic at the same point); env-reads now live in `cmd/core-svc/main.go`. Only
eventbus's intentional reads remain.
**Original shape: MISSING-ABSTRACTION | Severity: MED | Confidence: CONFIRMED | Priority: SOON**
```
$ git grep -l 'os.Getenv' -- internal/ ':!*_test.go'   → eventbus, identity/service, payment/service,
                                                          payment/sipay/client, shipping/service, storage/s3, storage/storage (7)
$ git grep -hc 'os.Getenv' -- 'cmd/*/main.go'          → 70 (correct: read once at the binary entry)
```
70 env reads live in `cmd/*/main.go` (the right place — read once, inject), but **7 modules read
env at runtime directly**, coupling them to the environment and making them harder to test in
isolation (this is *why* `payment/service.go` needs A-001). No `pkg/config` / `internal/config`
exists. Recommendation: a small config loader read in each `main.go`, injected into those modules
(see PR A4-3).

---

## §3.5 Public / internal API surface — VERIFIED-COMPLETE
Each module exports a single `Service` (+ `Repository`) interface from `api.go`; the boundary script
forbids importing the concrete struct/repository across modules. No exported test helpers found in
non-`_test.go` files. The external HTTP surface is OpenAPI-described (`api/openapi.yaml` + the
generated-sync gate in `openapi-ci.yml`). **No findings.**

---

## §3.6 Cross-service communication — VERIFIED-COMPLETE
- **core-svc → fin-svc:** Redis Streams events via the outbox (`internal/outbox`, `internal/eventbus`);
  no HTTP, no shared DB (CLAUDE.md §3.2). ADR-0003 documents the maxlen policy.
- **Crons → fin-svc:** thin `curl` to internal HTTP endpoints (`:8082/internal/v1/...`) — documented
  in `docs/internal/fin-svc-harness.md` (PR #72); the contract feeds A-001.
- **Object storage:** `internal/storage.PhotoStorage` (S3/B2 in prod, fs in dev) — ADR-0004.
- **No queues beyond Redis Streams; no shared filesystem.** Topology is coherent. **No findings.**

---

## §3.7 Data flow & coupling — VERIFIED-COMPLETE (no decomposition smell)
Spot-traced checkout→payment (the most cross-cutting flow): core-svc owns the order + payment-capture
HTTP path; the cashback/payout consequences happen in fin-svc **asynchronously** off the
`ecom.order.delivered.v1` event (CLAUDE.md §3.2) — so no single request opens transactions in two
services (no distributed-tx risk), and no request fans out across >3 services synchronously. The
event-driven seam is the decoupling. **No findings.**

---

## §3.8 Flutter feature architecture
Riverpod topology is healthy (T3-5 detector, PR #71: 95 providers all explicitly typed, 21 Notifiers
all conforming to a documented `build()` shape — see §4.1). One LOW finding on folder layout (A-005).

---

## §3.9 Testability gaps

### A-001 — payment has a PSP interface but no test/mock adapter (= T-016)
**✅ RESOLVED (A4-1) — was HIGH/NOW.** Discovery-shift: the gateway interface already existed as
`payment.Service` (adding `payment.Gateway` would duplicate it), so the real fix was construction:
`NewService(provider, cfg, repo) (Service, error)` (caller-injected, error-returning — no
`os.Getenv`/`log.Fatal`) + a configurable `internal/payment/paymenttest.Fake`. The os/exec
subprocess test is gone; `payment.Service` consumers are now testable. (Scoped out: sipay
`client.go`'s `GO_ENV` prod-safety check → A4-3; no `payment.Gateway` duplicate.)
**Original shape: MISSING-ABSTRACTION | Severity: HIGH | Confidence: CONFIRMED | Priority: NOW**
The PSP adapter pattern (CLAUDE.md §9) gives a provider-agnostic interface, but every adapter is a
real gateway and there is no fake to test against:
```
$ git grep -nE 'type Service .*interface' internal/payment/api.go   → internal/payment/api.go:14: type Service interface {
$ ls internal/payment/                                              → api.go craftgate domain.go errors.go iyzico reconciler.go repository.go service.go sipay
$ git grep -lniE 'mock|fake|stub' internal/payment ':!*_test.go'    → (only incidental words in service.go/errors.go — no mock ADAPTER)
$ git grep -nE 'os.Getenv' internal/payment/service.go internal/payment/sipay/client.go   → reads PSP keys directly
```
Impact: fin-svc payment/seller-payout paths can't be integration-tested without live gateway
credentials; the cron-overlap sim (PR #72) is BLOCKED on exactly this; and `payment/service.go`
reads PSP config from env directly (couples it to the environment — overlaps A-003). The would-be
test exists (§2.3): a `payment.fakeGateway` implementing `Service` lets the reconciler + cron paths
run hermetically — so the abstraction is the codebase's, not invented.
Recommendation: a `payment` test adapter (in-memory `Service` impl) + inject PSP config through the
constructor instead of `os.Getenv`. Then cron-overlap-sim + fin-svc integration tests unblock.
Refactor: ~400–600 LOC across payment + fin-svc wiring; risk **MED** (financial path, but additive
— no behaviour change to real adapters). Dependencies: none.

### A-004 — shipping carriers may lack a test-mode abstraction (T-016-shaped)
**Shape: MISSING-ABSTRACTION | Severity: MED | Confidence: PROBABLE | Priority: SOON**
`internal/shipping/service.go` reads `os.Getenv` directly and the carrier adapters (Aras/Yurtiçi/…
per CLAUDE.md §8) weren't traced for a fake. Contrast `internal/storage` which **is** properly
abstracted (`PhotoStorage` interface + `fs.go` test impl — VERIFIED, not a finding). Flagged PROBABLE
for the A-001 refactor PR to confirm/refute (the #59→#60 hypothesis pattern): if shipping has the
same no-fake shape, fold it into the same interface+inject refactor.

---

## §3.10 / §4.1 Documentation drift

### A-002 — CLAUDE.md (the constitution) drifted from the built architecture
**✅ RESOLVED (A4-2) — was MED/NOW.** Re-verified every §2.3 claim: marked antifraud/
antifraud_inference/einvoice **PLANNED**; fixed pkg names (logger→logx, tracing→otelx, httpx
middleware→otelx); flagged currency/i18n/dbx as never-built (with where each concept actually
lives); added a Built-vs-Planned note pointing at `check-module-boundaries.sh` as authoritative;
fixed the §4.6 `pkg/currency.Code` reference. Reconcile-only, no rule changed.
**Original shape: UNDOCUMENTED / DRIFT | Severity: MED | Confidence: CONFIRMED | Priority: NOW**
```
$ for m in einvoice antifraud antifraud_inference; do echo "$m: CLAUDE=$(grep -c internal/$m CLAUDE.md) exists=$([ -d internal/$m ] && echo yes || echo NO)"; done
  einvoice: CLAUDE=1 exists=NO   antifraud: CLAUDE=2 exists=NO   antifraud_inference: CLAUDE=1 exists=NO
$ ls pkg/   → crypto healthcheck logx mediaurl metrics otelx pagerduty slack timex
  (CLAUDE.md §2.3 lists pkg/logger, pkg/tracing, pkg/currency, pkg/i18n, pkg/httpx, pkg/dbx — none exist by those names)
```
CLAUDE.md §2.3 lists v7 modules that aren't built (`einvoice`, `antifraud`, `antifraud_inference`),
omits ~10 that are (`attachments`, `shipping`, `orderledger`, `storage`, `inbox`, `sitemap`, …), and
names `pkg/` packages that were since renamed (`logger`→`logx`, `tracing`→`otelx`). The constitution
doesn't mark built-vs-planned, so a reader (human or agent) can't tell what exists. Onboarding +
agent-instruction tax. Recommendation: a doc PR marking planned modules `(planned)`, correcting the
`pkg/` list, and completing the module table. ~40 LOC doc; risk LOW.

### A-006 — the financial core lacks architecture docs
**✅ RESOLVED (A4-4) — was MED/SOON.** Created `docs/internal/financial-core.md` — the 7
financial-path conventions consolidated with code sketches, a gating summary table, and a PR-time
review checklist; cross-linked from CLAUDE.md §4 + CONTRIBUTING.
**Original shape: UNDOCUMENTED | Severity: MED | Confidence: CONFIRMED | Priority: SOON**
`docs/internal/` has 8 docs (mostly tooling + a few modules) for 32 modules. Most modules are
self-explanatory, but the **intricate financial core** — `ledger`, `outbox`, `eventbus`,
`orderledger`, `reconcile` — has no `docs/internal/*` explaining the double-entry/outbox/event
topology (LEDGER_GUIDE.md is referenced in CLAUDE.md but `ls docs/` should confirm its currency).
This is the steepest onboarding cliff. Recommendation: one `docs/internal/financial-core.md` tracing
order→ledger→outbox→event→cashback/payout. ~150 LOC doc.

---

## §4.1 Drift findings (design vs. implementation) — VERIFIED-COMPLETE
The rules the prior arc gated show **zero drift**, and the gates are the evidence:
```
$ go run ./cmd/lint-discipline ./internal/... ./cmd/... ./pkg/...   → 0 findings
  (pool-acquire-inside-tx [PR #42/#47] + soft-deleted-user-consumer [PR #49] universally respected)
$ dart run tool/audit/riverpod_check.dart --check                   → 0 inferred, 21/21 notifiers conform
$ bash tool/audit/check_i18n.sh --strict ; make migration-check     → green (0 extras, 0 risky DDL)
```
Soft-ref discipline (CLAUDE.md §5), the three Notifier shapes, the user-state-consumer rule, and the
pool-in-tx rule are all enforced by perpetual gates and currently clean. This is the strongest
signal in the audit: the prior arc didn't just fix issues, it made the fixes *self-sustaining*.
(The one documentation drift is A-002 — code is correct, the doc lags.)

## §4.2 Naming consistency — VERIFIED-COMPLETE
Storage readers consistently use `Get*`/`Find*` (the basis of the soft-deleted analyzer's reader
prefixes); no `OrderId`/`order_id` casing drift in Go identifiers found. **No findings.**

## §4.3 Onboarding archaeology
Post-`make bootstrap` (PR #71), the two day-2 confusions are exactly A-002 (the constitution
misleads about what exists) and A-006 (the financial core has no map). Both are doc findings, already
captured. The flat Flutter feature folders (A-005) are the third.

### A-005 — Flutter feature folders are flat, not layered
**Shape: UNDOCUMENTED (convention) | Severity: LOW | Confidence: CONFIRMED | Priority: PARK**
```
$ ls mobile/lib/features/account/   → account_screen.dart current_user_provider.dart browsing_history_screen.dart ...
```
Features are flat (screens + providers in one dir) rather than `data/domain/presentation/`. Fine at
current scale; a documented convention (either "flat is intentional" in CONTRIBUTING, or a layering
guide) would prevent drift as features grow. PARK until a feature gets large enough to hurt.

### A-007 — per-handler auth-coverage sweep not verified
**Shape: BOUNDARY-VIOLATION (potential) | Severity: MED | Confidence: PROBABLE | Priority: SOON**
Auth middleware exists + is centralized, but whether *every* handler that needs protection applies it
wasn't traced exhaustively. Flagged PROBABLE — a good first task for the A-001 PR's reviewer or a
dedicated sweep (mirrors the PR #49 user-state sweep). A small `lint-discipline`-style analyzer
(unprotected mutating handler) could even gate it — a Step-3-adjacent follow-up.

---

## §5 Verified-complete categories (evidence above)
- **§3.1** service boundaries — `go list -deps` both directions + the boundary gate.
- **§3.3** layer discipline — no HTTP types in api.go; pgx.Tx is the documented exception.
- **§3.5 / §3.6** API surface + cross-service comms — single Service interface per module; events+outbox only.
- **§3.7** data flow — event-driven seam, no distributed tx.
- **§4.1** gated-rule drift — lint-discipline / riverpod / i18n / migration gates all green.
- storage abstraction (`PhotoStorage` + fs/s3); ADR practice (`docs/adr/0001–0004`); Riverpod topology (T3-5).

---

## §6 Recommended refactor sequence

### PR A4-1 — `feat/payment-test-adapter` (NOW) — closes A-001 (= T-016)
- In-memory `payment.Service` (fake gateway) + inject PSP config via constructor (replaces the
  `os.Getenv` reads in `payment/service.go`). Unblocks fin-svc payment integration tests **and** the
  Step-3 cron-overlap sim (T-008) **and** part of A-003.
- ~400–600 LOC; **risk MED** (financial path — additive, no real-adapter behaviour change).
- Split-bailout: ship the fake + injection first; wire the cron-sim in the follow-up.

### PR A4-2 — `docs/reconcile-constitution` (NOW) — closes A-002
- Mark planned modules `(planned)`, fix the `pkg/` list, complete the module table in CLAUDE.md §2.3.
- ~40 LOC doc; **risk LOW**. Cheapest high-value item (the constitution guides every future PR + agent run).

### PR A4-3 — `refactor/config-injection` (SOON) — closes A-003
- A small config loader read once in each `cmd/*/main.go`, injected into the 7 modules that read
  `os.Getenv` directly (eventbus, identity, payment, shipping, storage…). Improves testability
  (complements A-001/A-004). ~300 LOC; **risk MED**.

### PR A4-4 — `docs/financial-core` (SOON) — closes A-006
- `docs/internal/financial-core.md`: order→ledger→outbox→event→cashback/payout map. ~150 LOC doc; risk LOW.

### LATER / PARK
- **A-004** shipping carrier test-mode — confirm during A4-1; fold in if T-016-shaped.
- **A-007** per-handler auth sweep — a sweep PR, or a small analyzer (Step-3-adjacent).
- **A-005** Flutter feature layering — PARK (document the convention when a feature grows).

**Adjacent (carried from Step 3, not new):** idempotency-surface analyzer; the original T-016 is now
A-001 (this PR's NOW). **Total NOW+SOON:** ~4 PRs, ~1100 LOC + ~190 doc LOC; A-001 the only HIGH.
