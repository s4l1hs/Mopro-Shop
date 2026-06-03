# Audit-driven improvement roadmap

Tracks the multi-step audit-then-fix plan. Each step is **audit-first** (a read-only
report lands), then **focused fix PRs** act on the report's findings by ID. A step is
marked complete only when its fix PRs land — not when the audit lands.

| Step | Scope | Audit | Status |
|---|---|---|---|
| 1 | Cleanup (dead code / docs / tooling) | `CLEANUP_AUDIT.md` | ✅ **complete** — PRs #54 (audit) → #55 (confirmed removals + `unused` gate) → #56 (re-verify; net-zero). Tooling-blocked remainder (i18n / goldens / Riverpod) → Step 3. |
| 2 | **Testing / correctness / concurrency** | `docs/audits/TESTING_AUDIT.md` | ✅ **CLOSED** — every finding F-001→F-017 has a terminal outcome. #58 F-001; #59 F-006/F-011/F-012; #60 F-002(partial)/F-007/F-004/F-008/F-010/F-016→F-017; closure PR: wallet-integration gate + F-003 + F-017 (+ F-016 test unskipped). Deferred non-Step-2 passes (UNKNOWN tier): ×50 -race repro, N+1/EXPLAIN, migration-safety, Flutter DevTools rebuild. |
| 3 | **Tooling** (CI / build / migration / cron / deploy / static-analysis / dev-convenience automation) | `docs/audits/TOOLING_AUDIT.md` | ⏳ **audited** — 9 MISSING (3 HIGH), 2 EXISTS-AWKWARD, 0 REDUNDANT; 2 from-memory MISSINGs corrected to EXISTS-FINE (rollback, golden-diff). Build PRs T3-1…T3-6 pending (see below). |
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
2. **T3-3** `feat/dev-bootstrap` (SOON) — closes **T-005** (`make bootstrap`). ~50 LOC.
3. **T3-4** `feat/migration-and-discipline-linters` (SOON) — closes **T-006** (migration linter),
   **T-007** (pool-in-tx / soft-delete-consumer / idempotency discipline linter). ~320 LOC.
4. **T3-5** `feat/riverpod-shape-detector` (SOON) — closes **T-002** (extend `list_providers.dart`
   to classify the 3 Notifier shapes + flag inference). ~300–500 LOC.
5. **T3-6** `feat/nightly-and-cron-tooling` (SOON) — closes **T-009** (`nightly.yml` schedule),
   **T-008** (cron dry-run + overlap sim). ~230 LOC.

**Fix follow-ups from the T3-1/T3-2 build (NEW):**
- **T3-sweep-i18n** — remove the 163 dead keys + clear `i18n_usage_baseline.txt` (uses the T-001 analyzer).
- **T3-fix-stdlib-vulns** (NOW) — bump Go toolchain to 1.26.4+ (closes **T-014**), then drop
  `continue-on-error` from `govulncheck.yml` to make it required.
- **T3-fix-missing-i18n** — add the 10 missing translations + clear `i18n_missing_baseline.txt` (closes **T-015**).

LATER/PARK: **T-011** new-migration generator (LOW); merge_group support (LOW); 3 scripts missing
`set -euo pipefail` (LOW tidy-up). **Corrected to EXISTS-FINE (nothing to build):** T-012 rollback
automation, T-013 golden-diff (`golden_platform.dart`).
