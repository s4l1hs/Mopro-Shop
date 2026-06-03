# Audit-driven improvement roadmap

Tracks the multi-step audit-then-fix plan. Each step is **audit-first** (a read-only
report lands), then **focused fix PRs** act on the report's findings by ID. A step is
marked complete only when its fix PRs land — not when the audit lands.

| Step | Scope | Audit | Status |
|---|---|---|---|
| 1 | Cleanup (dead code / docs / tooling) | `CLEANUP_AUDIT.md` | ✅ **complete** — PRs #54 (audit) → #55 (confirmed removals + `unused` gate) → #56 (re-verify; net-zero). Tooling-blocked remainder (i18n / goldens / Riverpod) → Step 3. |
| 2 | **Testing / correctness / concurrency** | `docs/audits/TESTING_AUDIT.md` | ✅ **CLOSED** — every finding F-001→F-017 has a terminal outcome. #58 F-001; #59 F-006/F-011/F-012; #60 F-002(partial)/F-007/F-004/F-008/F-010/F-016→F-017; closure PR: wallet-integration gate + F-003 + F-017 (+ F-016 test unskipped). Deferred non-Step-2 passes (UNKNOWN tier): ×50 -race repro, N+1/EXPLAIN, migration-safety, Flutter DevTools rebuild. |
| 3 | **Tooling** (CI / build / migration / cron / deploy / static-analysis / dev-convenience automation) | `docs/audits/TOOLING_AUDIT.md` | ✅ **CLOSED** (PRs #62 audit → #63 → cleanup → closure bundle). All NOW/SOON findings resolved: dep-CVE scan, make help, i18n completeness+dead-key, Go bump, bootstrap, Riverpod gate, migration-safety, nightly soak. **Two carve-outs:** T-007 (3 flow-AST discipline checks) → `cmd/lint-discipline` follow-up; T-008 (cron-overlap sim) deferred (needs fin-svc harness). |
| 4 | **Architecture / modularity** | `docs/audits/ARCHITECTURE_AUDIT.md` | ⏳ **audited** — 1 HIGH (A-001 = T-016 payment test-mode), 3 MED, 1 LOW, 2 PROBABLE; most categories VERIFIED-COMPLETE (boundaries/layers/drift are gated-clean). Refactor PRs A4-1…A4-4 pending (see below). |
| 5 | Trendyol parity continuation | — | ⏳ not started |

> Steps 3-5 scopes are as referenced by the step prompts; Step 2's and Step 3's findings are
> enumerated here (see each audit). This file is updated as each step's audit + fix PRs land.

## Step 2 — fixes pending (from `TESTING_AUDIT.md` §8)
1. ✅ `payment.Reconciler` tests (F-001) — done in `test/payment-reconciler-coverage` (unit + integration, `-race`, gated). `payment.Service` impls + backup adapters remain → folded into F-002 module coverage.
2. ✅ identity `-race` target (F-006) — `integration-identity-race`, clean, gated (`test/audit-burndown-identity-treasury`).
3. ✅ REVIVAL_GAP triage + F-012 (F-011/F-012) — F-012 CONFIRMED+FIXED (jti); F-011: 3 restored, 1→F-016, 1 documented.
4. Per-module coverage: ~~treasury~~ (⚠️ stub — not-actionable) → `search` → `media` → `sizefinder` (F-002, MED). **Verify each is a real impl, not a stub, before writing tests.**
4b. NEW F-016 (LOW, test-infra): isolate identity integration tests' shared `integRedis`, then un-skip the rate-limiter test.
5. Small: wallet refresh-loop test, idempotency determinism test, retry backoff, DLQ ctx timeout, StateNotifier migration (F-003/F-007/F-008/F-010/F-004, LOW).
6. Deferred passes: migration-safety (§3.8), N+1/EXPLAIN (§3.5), ×50 `-race` repro (§6.3), Flutter rebuild-storm DevTools (§4.3).

## Step 3 — build PRs pending (from `TOOLING_AUDIT.md` §6)

The audit landed read-only; no tooling was built in it. Build sequence (NOW first, then SOON;
LATER/PARK unsequenced). Each build PR references its `T-ID`.

1. ✅ **T3-1 + T3-2** (bundled, `feat/step3-ci-hygiene-i18n-analyzer`) — **DONE.** Closed
   **T-003** (govulncheck + dependabot + `make govulncheck`), **T-004** (`make help` + 31
   annotations), **T-010** (`check_i18n.sh --strict` wired), **T-001** (zero-dep prefix-aware
   dead-key analyzer + dual baselines + CI gate). Surfaced **T-014** (2 called Go stdlib vulns)
   and **T-015** (10 missing i18n keys).
2. ✅ **T3-3** — closed **T-005** (`make bootstrap` + `scripts/bootstrap.sh`, idempotent).
3. ✅ **T3-4 (partial)** — closed **T-006** (`scripts/lint-migrations.sh` migration-safety, in
   `make verify`). **T-007 SPLIT:** the 3 flow-AST checks (pool-in-tx / soft-delete-consumer /
   idempotency) need `go/analysis` → focused **`cmd/lint-discipline`** follow-up (not greps).
4. ✅ **T3-5** — closed **T-002** (`tool/audit/riverpod_check.dart`: inferred-type ratchet [0 today]
   + informational shape inventory [all 21 notifiers conform]).
5. ✅ **T3-6 (partial)** — closed **T-009** (`nightly.yml` + `make soak`, ×50 -race). **T-008
   DEFERRED:** cron-overlap sim needs a fin-svc test harness to run the crons safely.

**Step 3 closure carve-outs:**
- ✅ **`cmd/lint-discipline`** (T-007) — carve-out PR shipped **pool-acquire-inside-tx** +
  **soft-deleted-user-consumer** (go/analysis, 0 findings, in `make verify`). **idempotency-surface**
  still split (hardest; SQL-shape, FP-prone) → its own focused follow-up.
- ⛔ **cron-overlap sim** (T-008) — **BLOCKED**: crons curl a fin-svc HTTP endpoint; a safe sim needs
  a fin-svc HTTP harness + mock PSP (none exists) → filed **T-016** (Step-4 product infra). Overlap-
  safety is already gated by idempotency-key UNIQUE + the cashback/payout integration tests.

**Remaining Step-3 tail:** idempotency-surface analyzer (focused PR); T-016/T-008 (Step-4 harness).

**Fix follow-ups from the T3-1/T3-2 build:** ✅ **ALL DONE** (`chore/step3-t014-i18n-cleanup`):
- ✅ **T3-sweep-i18n** — 163 dead keys removed across 4 locales; `i18n_usage_baseline.txt` cleared.
- ✅ **T-014** — bumped Go to **1.25.11** (go.mod/go.work/Dockerfile/workflows); `continue-on-error`
  removed → govulncheck is now a required gate. (Discovery corrected the target from 1.26.4: the CI
  scan against go 1.25 showed 9 called vulns, all fixed by the same-minor 1.25.11 patch.)
- ✅ **T-015** — 10 missing keys added to tr-TR + en-US; `i18n_missing_baseline.txt` cleared.

LATER/PARK: **T-011** new-migration generator (LOW); merge_group support (LOW); 3 scripts missing
`set -euo pipefail` (LOW tidy-up). **Corrected to EXISTS-FINE (nothing to build):** T-012 rollback
automation, T-013 golden-diff (`golden_platform.dart`).

## Step 4 — refactor PRs pending (from `ARCHITECTURE_AUDIT.md` §6)

The audit landed read-only; no code changed. The architecture is gated-clean — findings are narrow.

1. **A4-1** `feat/payment-test-adapter` (NOW) — **A-001 (= T-016, HIGH)**: in-memory `payment.Service`
   fake + inject PSP config (no more `os.Getenv` in `payment/service.go`). Unblocks fin-svc payment
   integration tests + the Step-3 cron-overlap sim (T-008). ~400–600 LOC, risk MED (financial path, additive).
2. **A4-2** `docs/reconcile-constitution` (NOW) — **A-002 (MED)**: mark CLAUDE.md's planned modules
   `(planned)`, fix the `pkg/` list, complete the module table. ~40 LOC doc, risk LOW.
3. **A4-3** `refactor/config-injection` (SOON) — **A-003 (MED)**: central config loader in each
   `main.go`, injected into the 7 env-reading modules. ~300 LOC, risk MED.
4. **A4-4** `docs/financial-core` (SOON) — **A-006 (MED)**: `docs/internal/financial-core.md`
   (order→ledger→outbox→event→cashback/payout map). ~150 LOC doc.

LATER/PARK: **A-004** shipping carrier test-mode (PROBABLE — confirm during A4-1); **A-007** per-handler
auth-coverage sweep (PROBABLE, maybe a small analyzer); **A-005** Flutter feature layering (PARK).

**Step-3 tail still open (adjacent):** idempotency-surface analyzer; T-016 is now A-001 (folded in).
