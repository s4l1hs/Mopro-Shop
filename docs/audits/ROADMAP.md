# Audit-driven improvement roadmap

Tracks the multi-step audit-then-fix plan. Each step is **audit-first** (a read-only
report lands), then **focused fix PRs** act on the report's findings by ID. A step is
marked complete only when its fix PRs land — not when the audit lands.

| Step | Scope | Audit | Status |
|---|---|---|---|
| 1 | Cleanup (dead code / docs / tooling) | `CLEANUP_AUDIT.md` | ✅ **complete** — PRs #54 (audit) → #55 (confirmed removals + `unused` gate) → #56 (re-verify; net-zero). Tooling-blocked remainder (i18n / goldens / Riverpod) → Step 3. |
| 2 | **Testing / correctness / concurrency** | `docs/audits/TESTING_AUDIT.md` | 🟡 **audited; fixes nearly done.** MED: F-001 (#58), F-006/F-011/F-012 (#59), F-002 partial (4 stubs not-actionable + payment.Service sliced). LOW: F-007 fixed; F-004/F-008/F-010 not-actionable; F-003 deferred (needs wallet-integration gate). Corrected: F-016. **Open: F-017** (NEW, rate-limiter ms-member undercount — product fix), F-003 gate, ungated-wallet-integration observation. |
| 3 | Tooling-blocked audits (i18n key usage, Riverpod inference classes — need usage-aware analyzers) | — | ⏳ not started |
| 4 | Architecture / modularity audit | — | ⏳ not started |
| 5 | (reserved) | — | ⏳ not started |

> Steps 3-5 scopes are as referenced by the step prompts; only Step 2's findings are
> enumerated here (see the audit). This file is updated as each step's audit + fix PRs land.

## Step 2 — fixes pending (from `TESTING_AUDIT.md` §8)
1. ✅ `payment.Reconciler` tests (F-001) — done in `test/payment-reconciler-coverage` (unit + integration, `-race`, gated). `payment.Service` impls + backup adapters remain → folded into F-002 module coverage.
2. ✅ identity `-race` target (F-006) — `integration-identity-race`, clean, gated (`test/audit-burndown-identity-treasury`).
3. ✅ REVIVAL_GAP triage + F-012 (F-011/F-012) — F-012 CONFIRMED+FIXED (jti); F-011: 3 restored, 1→F-016, 1 documented.
4. Per-module coverage: ~~treasury~~ (⚠️ stub — not-actionable) → `search` → `media` → `sizefinder` (F-002, MED). **Verify each is a real impl, not a stub, before writing tests.**
4b. NEW F-016 (LOW, test-infra): isolate identity integration tests' shared `integRedis`, then un-skip the rate-limiter test.
5. Small: wallet refresh-loop test, idempotency determinism test, retry backoff, DLQ ctx timeout, StateNotifier migration (F-003/F-007/F-008/F-010/F-004, LOW).
6. Deferred passes: migration-safety (§3.8), N+1/EXPLAIN (§3.5), ×50 `-race` repro (§6.3), Flutter rebuild-storm DevTools (§4.3).
