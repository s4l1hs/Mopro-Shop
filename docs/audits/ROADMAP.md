# Audit-driven improvement roadmap

Tracks the multi-step audit-then-fix plan. Each step is **audit-first** (a read-only
report lands), then **focused fix PRs** act on the report's findings by ID. A step is
marked complete only when its fix PRs land — not when the audit lands.

| Step | Scope | Audit | Status |
|---|---|---|---|
| 1 | Cleanup (dead code / docs / tooling) | `CLEANUP_AUDIT.md` | ✅ **complete** — PRs #54 (audit) → #55 (confirmed removals + `unused` gate) → #56 (re-verify; net-zero). Tooling-blocked remainder (i18n / goldens / Riverpod) → Step 3. |
| 2 | **Testing / correctness / concurrency** | `docs/audits/TESTING_AUDIT.md` | 🟡 **audited — fixes pending** (this PR). 0 CONFIRMED HIGH, 7 MED, 5 LOW. Fix sequence in TESTING_AUDIT §8. |
| 3 | Tooling-blocked audits (i18n key usage, Riverpod inference classes — need usage-aware analyzers) | — | ⏳ not started |
| 4 | Architecture / modularity audit | — | ⏳ not started |
| 5 | (reserved) | — | ⏳ not started |

> Steps 3-5 scopes are as referenced by the step prompts; only Step 2's findings are
> enumerated here (see the audit). This file is updated as each step's audit + fix PRs land.

## Step 2 — fixes pending (from `TESTING_AUDIT.md` §8)
1. `payment.Reconciler` + `payment.Service` tests (F-001, MED — live financial worker).
2. identity `-race` target excluding the bcrypt distribution test (F-006, MED).
3. Reconcile the 5 REVIVAL_GAP skips; verify F-012 (JWT same-second rotation collision) is stale-test vs real-bug (F-011/F-012, MED).
4. Per-module coverage: `treasury` → `search` → `media` → `sizefinder` (F-002, MED).
5. Small: wallet refresh-loop test, idempotency determinism test, retry backoff, DLQ ctx timeout, StateNotifier migration (F-003/F-007/F-008/F-010/F-004, LOW).
6. Deferred passes: migration-safety (§3.8), N+1/EXPLAIN (§3.5), ×50 `-race` repro (§6.3), Flutter rebuild-storm DevTools (§4.3).
