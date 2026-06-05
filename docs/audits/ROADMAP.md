# Audit-driven improvement roadmap

Tracks the multi-step audit-then-fix plan. Each step is **audit-first** (a read-only
report lands), then **focused fix PRs** act on the report's findings by ID. A step is
marked complete only when its fix PRs land — not when the audit lands.

| Step | Scope | Audit | Status |
|---|---|---|---|
| 1 | Cleanup (dead code / docs / tooling) | `CLEANUP_AUDIT.md` | ✅ **complete** — PRs #54 (audit) → #55 (confirmed removals + `unused` gate) → #56 (re-verify; net-zero). Tooling-blocked remainder (i18n / goldens / Riverpod) → Step 3. |
| 2 | **Testing / correctness / concurrency** | `docs/audits/TESTING_AUDIT.md` | ✅ **CLOSED** — every finding F-001→F-017 has a terminal outcome. #58 F-001; #59 F-006/F-011/F-012; #60 F-002(partial)/F-007/F-004/F-008/F-010/F-016→F-017; closure PR: wallet-integration gate + F-003 + F-017 (+ F-016 test unskipped). Deferred non-Step-2 passes (UNKNOWN tier): ×50 -race repro, N+1/EXPLAIN, migration-safety, Flutter DevTools rebuild. |
| 3 | **Tooling** (CI / build / migration / cron / deploy / static-analysis / dev-convenience automation) | `docs/audits/TOOLING_AUDIT.md` | ✅ **CLOSED** (PRs #62 audit → #63 → cleanup → closure bundle). All NOW/SOON findings resolved: dep-CVE scan, make help, i18n completeness+dead-key, Go bump, bootstrap, Riverpod gate, migration-safety, nightly soak. **Two carve-outs:** T-007 (3 flow-AST discipline checks) → `cmd/lint-discipline` follow-up; T-008 (cron-overlap sim) deferred (needs fin-svc harness). |
| 4 | **Architecture / modularity** | `docs/audits/ARCHITECTURE_AUDIT.md` | ✅ **CLOSED** — A-001 (payment test-mode, A4-1), A-002+A-006 (CLAUDE.md reconcile + financial-core doc, A4-2/A4-4), A-003 (config injection, A4-3) all resolved; A-004/A-007 PROBABLE, A-005 PARK. Most categories were VERIFIED-COMPLETE (boundaries/layers/drift gated-clean). |
| 5 | **Trendyol UI parity** | `docs/audits/TRENDYOL_PARITY_AUDIT.md` | ⏳ **audited — build PRs pending.** Honest outcome: **0 CONFIRMED HIGH** (design tokens + auth-gate, the would-be HIGHs, are VERIFIED-COMPLETE); 3 MED, 7 LOW, 6 PROBABLE, 12 VERIFIED-COMPLETE surfaces. Mopro is a mature, golden-covered, guest-aware app — remaining work is fidelity polish + backend-data wiring, not surface-building. Trendyol-side coverage-constrained (only homepage fetchable; `/sr`+PDP 403). |

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

## Step 4 — ✅ CLOSED (refactor PRs from `ARCHITECTURE_AUDIT.md` §6)

The audit landed read-only; no code changed. The architecture is gated-clean — findings were narrow.
All actionable findings (A-001/A-002/A-003/A-006) landed across A4-1…A4-4; A-004/A-007 PROBABLE,
A-005 PARK (carried as ROADMAP tail, not Step-4 blockers).

1. ✅ **A4-1** `feat/payment-gateway-inject` — **A-001 (HIGH) DONE**. Discovery-shift: the gateway
   interface already existed as `payment.Service`, so the fix was construction —
   `NewService(provider, cfg, repo) (Service, error)` (no `os.Getenv`/`log.Fatal`) + a configurable
   `paymenttest.Fake`. payment.Service consumers are now testable. **T-016 mock-PSP part resolved**;
   the fin-svc HTTP harness (cron-sim) remains separate. (sipay `GO_ENV` deferred to A4-3.)
2. ✅ **A4-2** (`docs/reconcile-constitution-financial-core`) — **A-002 DONE**: CLAUDE.md §2.3
   reconciled (PLANNED markers, pkg names fixed, Built-vs-Planned note); §4.6 currency.Code stale
   ref removed.
3. ✅ **A4-3** `refactor/config-injection` — **A-003 (MED) DONE**. Discovery-shift: of the audit's 7
   modules, payment was already cleared (#74) and **eventbus is intentional** (ADR-0003 per-stream
   MAXLEN tuning, §2.2 — reclassified, not migrated). The 4 real reads injected: sipay
   (`SipayConfig.Environment` — **clears the A4-1-deferred `GO_ENV` invariant**), storage (`storage.Config`),
   shipping (`inProduction bool`), identity (`WithDevOTPBypass` functional option — zero test-caller
   cascade on the auth core). Each prod-safety guard preserved verbatim. Final sweep: only eventbus's
   intentional `os.Getenv` remains. **Step 4 CLOSED.**
4. ✅ **A4-4** (same PR) — **A-006 DONE**: `docs/internal/financial-core.md` — 7 conventions
   consolidated with sketches, gating table, review checklist; cross-linked from CLAUDE.md + CONTRIBUTING.

LATER/PARK: **A-004** shipping carrier test-mode (PROBABLE — confirm during A4-1); **A-007** per-handler
auth-coverage sweep (PROBABLE, maybe a small analyzer); **A-005** Flutter feature layering (PARK).

**Open tail carried past Step 4 (non-blocking follow-ups):** idempotency-surface analyzer (T-007
split); cron-overlap sim (T-008, needs fin-svc HTTP harness); the PR #74 chi-square flake
(`TestProperty_OTPCodeDistribution`, candidate finding). A-004/A-007 PROBABLE; A-005 PARK.

## Step 5 — parity PRs pending (from `TRENDYOL_PARITY_AUDIT.md` §6)

The audit landed read-only; no UI changed. **Honest discovery-shift:** the two findings that would
have been foundational HIGHs — design-token systematization (P-001) and auth-gate consistency (P-025)
— are **already VERIFIED-COMPLETE** (`design/tokens.dart`+`theme.dart`; the single guest-preserving
`requireAuth` helper). So there is **no foundational PR to land first**; the sequence is fidelity polish
+ backend-data wiring + PROBABLE-confirmation. Build sequence (NOW first):

1. ✅ **P5-1 + P5-2** `feat/parity-card-pdp-polish` (PR #78) — **DONE.** Bundled. Closed **P-005** (card price →
   `cs.primary`), **P-006** (shared `DiscountPill` on the `cs.error`/destructive token — card + PDP), **P-020**
   (`primaryDark` #E36925 → #E97230, 4.66:1 on `surfaceDark`, contrast backlog cleared). 35 dark-mode goldens
   re-baselined on Linux. **P-014 SPLIT OUT** — discovery found its true scope is ~55 strings cross-app (11 `Text()`
   + ~40 `app_router.dart` `t()` tab-titles + auth_layout + search-title) + a `t()` helper refactor, far past a
   card/PDP-polish PR (§6/§9 split). → **`feat/i18n-hardcoded-sweep`** (NOW slot).
2. ✅ **P5-i18n-sweep — P-014 CLOSED.** Full app i18n hardcoded-string sweep across **7 phased PRs**: Phase 1
   (#79 app_router titles, 44 keys) · 2a+2c (#80 auth + sipay, ~58) · 2b (#81 account, 57) · 2d (#82 verification +
   marketing, ~34) · **2e+2f (#83 checkout + singletons + home stragglers, ~32) — closes P-014.** True scope ran
   **~250+ strings / ~30 files** (the diacritic grep undercounted ~2× each phase). 0 hardcoded TR left in UI sinks;
   tr-TR (master) + en-US; 0 TRANSLATION_NEEDED. Canonical i18n template: full-file reads, key+JSON test pattern (no
   bundle), const→build-time lists, golden-prediction, orphaned-widget findings.
3. ✅ **P5-wire-filters — discover-and-bifurcate (Outcome C).** `feat/wire-plp-filters` — **P-026 closed as
   `BLOCKED-BY-BACKEND-GAP`.** Discovery (`docs/internal/p026-filter-wiring.md`) traced every filter dimension
   through all six layers: the frontend (`PlpFilters` state + URL codec + sidebar panel + mobile sheet + chips) is
   fully built, but `/products` + `/search` apply **no** filter or sort server-side (even spec-declared params are
   dropped at the handler). 0 filters wired; full-stack gap filed as **P-028 (HIGH, backend)**. The frontend-wiring
   PR is queued behind P-028 (substrate ready — discovery §9).
   **Update — P-028 ✅ RESOLVED** (`feat/catalog-filter-api`, `docs/internal/p028-filter-sort-api.md`): the backend
   now filters (price/brand/rating/free_shipping/in_stock/category) + sorts (5 tokens) end-to-end; migration 0081
   adds `products.free_shipping`; 19 integration subtests. `bestseller` sort carved → **P-029 ✅ RESOLVED**
   (`feat/bestseller-sort`, Pattern B — analytics is in-process so the constraint never bit; category-scope → P-031).
   **P-026 ✅ RESOLVED** (`feat/wire-frontend-filters`) — the filter UI now drives the
   fetch end-to-end (price/brand/rating/free_shipping/in_stock/sort on PLP + search); `bestseller` hidden +
   `cashback_only` disabled per P-029/P-028. Filters are functional.
4. **P5-3** `feat/pdp-delivery-eta` (SOON) — closes **P-007** + lights up the dark **P-008b** UI. **Backend-gated**
   (catalog/shipping API must expose ETA + original price + lowest-30d); UI slot can land NOW, data SOON. Risk MED.
5. **P5-4** `feat/parity-card-badges` — ✅ **P-004 + P-009 RESOLVED** (backend `feat/productsummary-enrich`;
   frontend `feat/wire-card-badges`). The card renders the favorites-count overlay (`formatCompactCount`) +
   free-shipping/discount badges end-to-end. Bestseller badge stays deferred (→ P-029). The PDP count/badge
   is out of scope (card-scoped findings; PDP uses the un-enriched full `Product`).
6. **P5-5** `feat/bestseller-sort` — ✅ **P-029 RESOLVED** (`docs/internal/p029-bestseller-architecture.md`,
   Pattern B). The prompt assumed a service boundary needing denormalize-via-outbox (Pattern A) or HTTP; discovery
   found analytics is an **in-process** core-svc module with `PopularProductIDs` already wired, so the catalog
   handler reads the global popularity ranking + passes ordered IDs to the repo (`ProductFilter.PopularIDs`),
   which orders by `array_position(...) NULLS LAST` — **no cross-schema JOIN, no schema change, no sync infra**.
   Spec re-adds `bestseller`; empty popularity → recommended. Global scope only → category-scope carved → **P-031**
   (MED, analytics: populate `category:{id}` scopes + a scoped `PopularProductIDs`).
7. **P5-6** `feat/bestseller-unhide` — ✅ **P-029 frontend un-hide** (`docs/internal/p029-frontend-unhide.md`).
   Removed the two `.where(... != bestseller)` filters PR #86 added (mobile `SortSheet` + desktop `PopupMenuButton`);
   bestseller now renders in every sort selector and `sort=bestseller` flows to the backend as a raw string (no
   dependency on #90's client regen). i18n already correct + matches the home rail (`"Çok satanlar"`, kept); URL
   codec already round-trips; **zero golden flips** (the option only lives in the tapped overlay). **P-029 closed
   end-to-end.**

✅ **LOW tail triaged (`chore/step5-low-batch`):** P-015 FIXED (out-of-stock variant chips disabled); P-011
CORRECTED (cart *has* a coupon field — `OrderSummaryCard`; the audit cited the orphaned `cart_totals_summary.dart`);
P-004 + P-009 NOT-ACTIONABLE (backend-gated — `ProductSummary` enrichment needed); P-012 + P-013 NOT-ACTIONABLE
(documented stepper design / PARK collections); **HeroCarousel REMOVED** (orphaned). Still PARK *if product wants*:
cart cross-sell + saved-for-later (P-011 b/c); favorite collections (P-013). Drive-by (Step-1 family, not parity):
the empty `mobile/lib/features/orders/` directory remains (out of this batch's scope).

**12 VERIFIED-COMPLETE surfaces** (design tokens, auth-gate/guest-browsing, global nav, home, flash deals, product
card, PDP structure, search/PLP filters (✅ functional — P-028 backend + P-026 frontend), reviews, Q&A, orders/returns, notifications/account/empty-states/responsive)
— see audit §5. **Do not rebuild these.**

**Step-5 coverage caveat:** Trendyol bot-blocks parametrized pages (403 on `/sr`, PDP, category; login-gated
account/cart/orders). Only the homepage fetched cleanly (2026-06-03), so ~19/20 surfaces have CONFIRMED *Mopro*
evidence but PROBABLE *Trendyol* comparison — each PROBABLE finding gets re-confirmed in its build PR's discovery
phase (#59→#60 pattern).

**Open tail (unchanged, non-blocking):** idempotency-surface analyzer (T-007 split); cron-overlap sim (T-008);
PR #74 chi-square flake; A-004/A-007 PROBABLE; A-005 PARK. **P-029 ✅ RESOLVED end-to-end** (backend
`feat/bestseller-sort`, Pattern B — analytics is in-process, so the catalog handler reads `PopularProductIDs` +
orders via `array_position`; no cross-schema JOIN, no schema change, no sync infra; global scope, category-scope
carved → **P-031**; frontend un-hide `feat/bestseller-unhide`). P-026 ✅ RESOLVED (frontend wired,
`feat/wire-frontend-filters`). **LOW tail + HeroCarousel
closed** (`chore/step5-low-batch`: P-015 FIX, P-011 CORRECTED, P-004/009/012/013 NOT-ACTIONABLE, HeroCarousel
REMOVED). ProductSummary enriched (`feat/productsummary-enrich`) **then P-004 + P-009 ✅ RESOLVED**
(`feat/wire-card-badges`: favorites-count overlay + free-shipping/discount card badges, end-to-end).
**The pure-UI Trendyol-parity work is complete.** Remaining Step-5 tail (all backend/architectural): P-007
(delivery-ETA), **P-030** (price-history / lowest_30d — HIGH compliance), P-031 (category-scoped bestseller),
chi-square flake.
