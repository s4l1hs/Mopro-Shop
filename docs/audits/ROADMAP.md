# Audit-driven improvement roadmap

Tracks the multi-step audit-then-fix plan. Each step is **audit-first** (a read-only
report lands), then **focused fix PRs** act on the report's findings by ID. A step is
marked complete only when its fix PRs land — not when the audit lands.

| Step | Scope | Audit | Status |
|---|---|---|---|
| 1 | Cleanup (dead code / docs / tooling) | `CLEANUP_AUDIT.md` | ✅ **complete** — PRs #54 (audit) → #55 (confirmed removals + `unused` gate) → #56 (re-verify; net-zero). Tooling-blocked remainder (i18n / goldens / Riverpod) → Step 3. |
| 2 | **Testing / correctness / concurrency** | `docs/audits/TESTING_AUDIT.md` | ✅ **CLOSED** — every finding F-001→F-017 has a terminal outcome. #58 F-001; #59 F-006/F-011/F-012; #60 F-002(partial)/F-007/F-004/F-008/F-010/F-016→F-017; closure PR: wallet-integration gate + F-003 + F-017 (+ F-016 test unskipped). Deferred non-Step-2 passes (UNKNOWN tier): ×50 -race repro, N+1/EXPLAIN, migration-safety, Flutter DevTools rebuild. |
| 3 | **Tooling** (CI / build / migration / cron / deploy / static-analysis / dev-convenience automation) | `docs/audits/TOOLING_AUDIT.md` | ✅ **CLOSED** (PRs #62 audit → #63 → cleanup → closure bundle). All NOW/SOON findings resolved: dep-CVE scan, make help, i18n completeness+dead-key, Go bump, bootstrap, Riverpod gate, migration-safety, nightly soak. **Two carve-outs:** T-007 (3 flow-AST discipline checks) → `cmd/lint-discipline` follow-up; T-008 (cron-overlap sim) deferred (needs fin-svc harness). |
| 4 | Architecture / modularity audit | — | ⏳ not started |
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

**Step 3 closure carve-outs (the only remaining Step-3 work):**
- **`cmd/lint-discipline`** (T-007) — 3 `go/analysis` analyzers + `analysistest`, ratcheted.
- **cron-overlap sim** (T-008) — revisit once a fin-svc harness exists.

**Fix follow-ups from the T3-1/T3-2 build:** ✅ **ALL DONE** (`chore/step3-t014-i18n-cleanup`):
- ✅ **T3-sweep-i18n** — 163 dead keys removed across 4 locales; `i18n_usage_baseline.txt` cleared.
- ✅ **T-014** — bumped Go to **1.25.11** (go.mod/go.work/Dockerfile/workflows); `continue-on-error`
  removed → govulncheck is now a required gate. (Discovery corrected the target from 1.26.4: the CI
  scan against go 1.25 showed 9 called vulns, all fixed by the same-minor 1.25.11 patch.)
- ✅ **T-015** — 10 missing keys added to tr-TR + en-US; `i18n_missing_baseline.txt` cleared.

LATER/PARK: **T-011** new-migration generator (LOW); merge_group support (LOW); 3 scripts missing
`set -euo pipefail` (LOW tidy-up). **Corrected to EXISTS-FINE (nothing to build):** T-012 rollback
automation, T-013 golden-diff (`golden_platform.dart`).
