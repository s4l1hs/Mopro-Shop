# CLEANUP_AUDIT.md

> **Read-only inventory.** No code is removed in the PR that produced this file.
> Subsequent focused PRs act on the §10 roadmap. Every finding cites file:line,
> severity, and effort; false-positive-prone heuristics are flagged as **candidate
> pools** (manual review required), never as confirmed dead lists.

> ## Execution status — `chore/project-cleanup-confirmed` (the confirmed half)
> **✅ CLOSED:** §4 root cause (golangci `unused` enabled) · §3 Go dead symbols
> (~30 removed) · §3.0 `core_impl.go` CoreServer stub (deleted, Option B) · §5 the
> unadopted `Mopro*` widgets + `_LoadingSpinner` consolidation · §6.5 the 3 unused
> pubspec deps. Added on-demand `make deadcode`.
> **⚠️ RECLASSIFIED as build-tag false positives (KEPT, not dead):** `wallet.RefreshWorker`
> and sipay `SignPayment3D`/`SignGetToken`/`SignWebhook` — used by `//go:build integration`
> tests that the audit's default-config `deadcode` run didn't analyze. The audit's
> "spot-verified no build-tag FPs" was incomplete; re-verification against all `*_test.go`
> caught it. So the "37 Go symbols" headline was ~30 after this correction.
> **✅ VERIFIED NOT ACTIONABLE — `chore/cleanup-cheap-followup`:** §7 docs (0 rot — CONTRIBUTING
> refs to removed symbols are the correct #55 notes; deploy docs current) · §8 tooling (0 dead —
> `api-check-sync` is a dev convenience; the 9 "unreferenced" scripts are cron/manual/ops, incl.
> the production `cashback-monthly-cron`/`seller-payout-daily-cron`) · §9 `var _ =` (0 instances;
> the reconcile one was the only occurrence, removed in #55) · post-`unused`-gate findings (0).
> Net removals that PR: 0. Evidence: `tool/audit/cheap_cleanup_baseline.md`.
> **⏳ TOOLING-BLOCKED (need usage-aware analyzers, not grep — step 3 of the plan):** §6.2 i18n
> keys (192, easy_localization prefix-building) · §6.4 goldens (56, interpolated names) · §5.2
> Riverpod inference classes (riverpod_lint-style awareness). §9 error-widget consolidation
> remains an optional UI-affecting refactor (not dead code), deferred.

## Executive summary

Audited at `main@ca739bf4` (2026-06-02). Backend ~42k Go LOC (366 files), frontend
~36k Dart LOC (687 files). Two green gates pre-empt whole classes of deadness:
`go test ./...`/`go build` (so no test references deleted code) and Flutter's strict
`very_good_analysis` (`flutter analyze` = **"No issues found!"** — no private unused
elements/imports/dead_code). **But `.golangci.yml` does NOT enable `unused`/`deadcode`**,
so Go dead code accumulates uncaught — that is where the real backend findings are.

| Domain | Confirmed findings | Candidate pools (manual review) | Headline |
|---|---|---|---|
| Backend Go | ~37 dead symbols + 1 dead stub file (41 methods) | — | `internal/api/core_impl.go` 501-stub never wired; scattered dead helpers/workers |
| Backend deps | 0 | — | `go.mod` is **tidy** (clean) |
| Frontend Dart | ~20 credible dead widgets/screens (incl. unadopted `Mopro*` shared widgets) | 47 Riverpod-pattern + 9 DTO classes | shared-widget set built (U8a) but never adopted |
| Frontend deps | 3 unused pubspec deps | — | `carousel_slider`, `fl_chart`, `json_annotation` |
| Frontend assets/i18n/goldens | 0 unused assets | 192 i18n keys, 56 goldens | grep can't resolve interpolation — needs tooling |
| Docs | 0 broken | 31 accreting audit baselines, large REPORT/CONTRIBUTING | accumulation, not rot |
| Tooling | 0 dead | 1 standalone make target, ~9 cron/manual scripts | all explained, none truly dead |
| Duplicates | 2 (`_LoadingSpinner`×2; ~7 ad-hoc error widgets) | — | consolidation opportunities |

**Recommended ordering:** (1) backend dead symbols [mechanical, XS–S], (2) frontend
pubspec deps [XS], (3) frontend dead widgets incl. `Mopro*` decision [S–M], (4) the
`core_impl.go` architectural decision [discuss], (5) duplicates consolidation [S],
(6) i18n/goldens **only after** adopting a proper usage tool. **Estimated 4–5 focused
sessions.** Neither stack hits the §1.6 ≥200-high-severity threshold; one combined arc
is feasible, but per-domain PRs are recommended for reviewability.

---

## §1. Snapshot

| Metric | Value |
|---|---|
| `main` SHA | `ca739bf4406b7bb685ed245ca635c658d2a7afd5` |
| Go LOC | 42,143 non-test / 26,084 test (366 `.go` files) |
| Dart LOC | 35,875 `lib/` / 23,076 `test/` (687 `.dart` files) |
| `cmd/` entries | core-svc, fin-svc, jobs-svc, migrate-tool, mopro (5) |
| `internal/` packages | 32 · `pkg/` dirs: 10 |
| Required CI check | `verify` (single; from PR #50) |
| `make verify` runtime | ~9 min (CI, 2-vCPU) |
| golangci-lint enabled | depguard, gocyclo, errcheck, revive, gosec, gocritic — **no `unused`/`deadcode`** |
| Flutter lint | `very_good_analysis` (strict); `flutter analyze` → 0 issues |

## §2. Tooling outputs

Raw evidence committed under `tool/audit/cleanup_raw_outputs/` (see its `README.md`).
Tools: staticcheck 2026.1 (v0.7.0), `golang.org/x/tools/cmd/deadcode`, golangci-lint
2.12.2, flutter 3.44 / dart 3.12. `staticcheck`/`deadcode` were installed ad-hoc for
this audit (not added to the repo — non-goal).

---

## §3. Backend (Go) dead code inventory

Sources: `go_staticcheck_U1000.txt` (unexported unused — types/fields/funcs),
`go_deadcode_test.txt` (whole-program unreachable funcs; roots = all `main`s + tests).
All entries below were **spot-verified to not be build-tag false positives** (the
flagged files carry no `//go:build` constraint hiding a caller).

### 3.0 Architectural finding (§1.6 trigger #2) — `internal/api/core_impl.go`

`CoreServer` implements the generated `gencore.StrictServerInterface`; **all 41 methods
return 501 Not Implemented** and the type is **never instantiated anywhere** (`rg
CoreServer` finds only the file itself). Header: *"All methods return 501 in Phase 4.0.
Live handler migration happens in Phase 4.4+."* The live HTTP surface is the stdlib mux
in `cmd/core-svc/main.go` instead. **This is a deliberate-scaffolding decision, not a
mechanical removal:** either the OpenAPI strict-server migration is still planned (keep,
add a tracking issue) or it was abandoned (delete `core_impl.go` + possibly the unused
`gen/core` server half). 41 dead methods. **Severity: High · Effort: M · Decision required.**

### 3.1 Dead funcs/methods (whole-program unreachable) — confirmed

| Symbol | File:line | Exported? | Sev | Eff |
|---|---|---|---|---|
| `RefreshWorker` (NewRefreshWorker, Run, RefreshOnce, refresh) | `internal/wallet/refresh_worker.go:21,32,53,57` | Yes | High | S |
| `NewNoopDLQRepository` + `noopDLQRepository.*` (7) | `internal/eventbus/dlq.go:367,369,372,375,376,379,380` | mixed | Med | S |
| `NewNoopDedupStore`,`NewInTxDedupStore`,`inTxDedupStore.MarkSent`,`noopDedupStore.MarkSent` | `internal/notification/dedup.go:55,58,66,68` | Yes | Med | S |
| `SignPayment3D`,`SignGetToken`,`SignWebhook` | `internal/payment/sipay/hmac.go:41,52,63` | Yes | High | S |
| `circuitBreaker.isOpen`,`redact`,`Adapter.doJSONIdempotent` | `internal/payment/sipay/client.go:110,219,303` | mixed | Med | S |
| `RequireStepUp`,`ClaimsFromCtx` | `internal/identity/middleware/auth.go:87,128` | Yes | High | S |
| `ContextWithSellerID` | `internal/identity/middleware/seller.go:57` | Yes | Med | XS |
| `NewPgxCalendarLoader`,`pgxCalendarLoader.Load` | `pkg/timex/loader.go:18,22` | Yes | Med | S |
| `tracing.Init` (**`// Deprecated:`** — superseded by `pkg/otelx.Init`) | `pkg/tracing/tracing.go:17` | Yes | High | XS |
| `buildCheck1DedupKey`,`buildCheck2DedupKey` | `internal/reconcile/checks.go:31,68` | No | Low | XS |
| `handleGetProduct` | `cmd/core-svc/main.go:963` | No | Med | XS |

Notable: `RequireStepUp` (exported step-up auth **middleware**, unwired — verify HTTP-layer
step-up enforcement isn't expected here), `SignWebhook`/`SignPayment3D`/`SignGetToken`
(sipay HMAC, unused → the sipay PSP adapter is incompletely wired), `tracing.Init`
(deprecated shim). Full list: `go_deadcode_test.txt`.

### 3.2 Dead unexported types/fields/vars (staticcheck U1000) — confirmed

| Symbol | File:line | Sev | Eff |
|---|---|---|---|
| `orderScanner` (type) | `internal/order/repository.go:184` | Med | XS |
| `cmdKey` (type) | `pkg/metrics/redis.go:37` | Low | XS |
| `tokenMu`,`token`,`tokenExp` (fields) | `internal/sellerpayout/sipay/transfer.go:44-46` | Med | XS |

### 3.3 Test-only dead helpers (used by no test)

| Symbol | File:line | Sev | Eff |
|---|---|---|---|
| `validInput` | `internal/wallet/wallet_unit_test.go:110` | Low | XS |
| `IssueTestStepUpToken` | `internal/identity/testutil/jwt.go:36` | Low | XS |

### 3.5 Dead `cmd/` entries — none

`migrate-tool` and `mopro` are absent from `build-images.yml`'s matrix but are
**intentional CLIs** (migrations / ops) per CLAUDE.md §2.3. Not dead.

### 3.6 / 3.7 Dead migrations · orphan test files — none found

The `_test.go`-without-same-name-`.go` heuristic produced ~60 hits but is **false-positive
by design in Go** (no filename pairing; e.g. `cmd/core-svc/*_handler_test.go` test handlers
defined in `main.go`; `internal/analytics/` has 5 production files under other names). Since
`go test ./...` is green, no test references deleted production code. No migration cross-ref
anomalies surfaced. **No real findings.**

**§3 subtotal: ~37 confirmed dead symbols + 1 stub file (41 methods, decision).**

---

## §4. Backend dependencies

`go mod tidy -diff` → **empty**. `go.mod` is tidy: no unused `require`s, no version
drift. **0 findings.** (Evidence: `go_mod_tidy_diff.txt`, 0 bytes.)

---

## §5. Frontend (Dart/Flutter) dead code inventory

`flutter analyze` → **"No issues found!"** under strict `very_good_analysis`. So
*private* deadness (unused elements/fields/imports, `dead_code`) is already clean. The
analyzer cannot see cross-file *public* deadness; the scans below fill that gap but are
heuristic.

### 5.1 Dead widgets/screens — credible (high-confidence subset)

`dart_dead_classes.txt` has 83 candidates. **47 are Riverpod Notifier/State/Controller/
Provider/Cache classes and 9 are DTO/Result types — these are false-positive-prone**
(referenced via their provider, by type inference, or composed within their own file;
verified e.g. `cartRepositoryProvider`/`AuthNotifier` are file-internal-live). The **20
actual-widget/screen candidates** below were verified to have **0 references in `lib/`+
`test/`** (`rg -w`); each still needs a ~30-second manual confirm before removal.

**Confirmed cluster — unadopted `Mopro*` shared widgets (built in U8a 2026-05-24, never adopted; app uses Material `FilledButton`/`TextButton`):**

| Widget | File | Evidence | Sev | Eff |
|---|---|---|---|---|
| `MoproButton` | `lib/widgets/mopro_button.dart` | 0 refs; `FilledButton` used in 43 files instead | High | S |
| `MoproInput` | `lib/widgets/mopro_input.dart` | 0 refs anywhere | High | S |
| `PriceDisplay` | `lib/widgets/price_display.dart` | 0 refs anywhere | High | S |
| `MoproChip`,`MoproChoiceGroup` | `lib/widgets/mopro_chip.dart` | 0 refs | High | S |
| `MoproSheet` | `lib/widgets/mopro_sheet.dart` | 0 refs | High | S |
| `MoproAppBar` | `lib/shell/mopro_app_bar.dart` | 0 refs | Med | S |

(`lib/widgets/star_rating.dart`, `skeleton_box.dart`, `theme_toggle.dart`, `mopro_badge.dart`
are **used** — not flagged. The finding is the *subset*, not the whole dir.)

**Other credible dead widgets/screens (0 refs; confirm before removal):**
`BottomNavShell` (`lib/core/widgets/bottom_nav_shell.dart`), `ProfileTabScreen`
(`lib/features/profile/profile_tab_screen.dart`), `AccountPlaceholderScreen`,
`Checkout3dsWebviewScreen`, `HeroCarousel`/`FilterSheet`/`SortSheet`/`CategoryChip`
(`lib/features/catalog/widgets/`), `ThemedImageIcon`, `HoverRegion`, `AdaptiveValue`,
`MainContentScope`, `CancelOrderContent`. **Sev: Med · Eff: S each.** Full list +
the FP-prone 56: `dart_dead_classes.txt`.

### 5.2 Dead Riverpod providers — candidate pool (low confidence)

`dart_dead_providers.txt` (13) is **FP-dominated**: `apiClientProvider`,
`cartRepositoryProvider`, `secureStorageProvider`, etc. are consumed via `ref.watch`/
composition within their own file or via codegen. **Not a removal list** — manual review.

### 5.5 Unreachable routes — not separately confirmed

Routing is distributed (no single `router.dart`); the credible dead *screens* in §5.1
(`ProfileTabScreen`, `Checkout3dsWebviewScreen`, `AccountPlaceholderScreen`) are the
route-reachability signal. Confirm against the `GoRoute` table during the cleanup PR.

**§5 subtotal: ~20 credible dead widgets/screens (6 high-confidence `Mopro*`); 56 candidates need review.**

---

## §6. Frontend assets + i18n

### 6.1 Unused assets — none
8 files under `assets/images`+`assets/data`; **all referenced**. (Bulk of assets are
`translations/` + `google_fonts/`, both used.) **0 findings.**

### 6.5 Unused pubspec dependencies — confirmed

| Dep | Evidence | Sev | Eff | Action |
|---|---|---|---|---|
| `carousel_slider` | 0 `package:` imports in lib/+test/ | Med | XS | remove |
| `fl_chart` | 0 imports | Med | XS | remove |
| `json_annotation` | 0 imports in app (codegen lives in `mopro_api` pkg) | Low | XS | remove after confirming no app-level `.g.dart` needs it |
| `cupertino_icons` | 0 imports but **implicit** (icon font) | — | — | **keep** (false positive) |

### 6.2 Unused i18n keys — candidate pool, HIGH false-positive (needs tooling)

740 leaf keys in `tr-TR.json`; 192 unmatched by exact full-string grep. **Sampling shows
a very high FP rate** — easy_localization builds keys by prefix/interpolation
(`common.*`, `auth.*` prefixes are referenced; full keys aren't). This is **NOT a dead
list.** Recommend a build-time key-usage checker (or `easy_localization`'s generator with
strict mode) before any removal. Evidence + caveat: `dart_unused_i18n_keys.txt`.

### 6.4 Orphan goldens — candidate pool, HIGH false-positive

149 golden PNGs; 56 stems unreferenced (excluding `failures/` debris which is **already
gitignored**, line 64, and untracked — not a finding). **Confirmed FP source:** interpolated
golden names, e.g. `matchesGoldenFile('goldens/refund_card_${status}_light.png')` and
`..._1024_$b.png`. The `refund_card_*`/`timeline_*` clusters are the most likely real
orphans but need per-cluster manual review. Evidence: `dart_orphan_goldens.txt`.

### 6.3 Stale build artifacts — none
`mobile/build/`, `.dart_tool/`, and `test/**/failures/` are correctly `.gitignore`d; none tracked.

**§6 subtotal: 3 removable deps; i18n/goldens deferred to tooling-assisted review.**

---

## §7. Documentation

- **§7.1 CONTRIBUTING.md** — actively maintained (this audit's predecessor PRs #51/#52
  corrected stale notes in-flight). It has grown to ~860 lines of per-PR pattern sections;
  **accumulation, not rot.** Candidate for thematic consolidation. Sev: Low · Eff: M.
- **§7.2 REPORT.md** — append-only per-PR log, ~3,900 lines. No broken-ref sweep performed
  (out of cheap-scan scope); recommend a link-checker pass in the docs cleanup PR. Sev: Low.
- **§7.4 `tool/audit/*.md`** — **31 historical baselines** (one per recent PR, per the
  CLAUDE.md audit-first convention). Valuable for traceability but accreting; consider an
  `tool/audit/archive/` after N PRs. Sev: Low · Eff: S.
- **§7.3/§7.5 deploy docs / ADRs** — `docs/deploy.md` + runbooks were refreshed in PRs
  #51–#53 (IMAGE_NS, deploy workflow). No `/docs/adr/` directory exists. No findings.

**§7 subtotal: 0 rot; accumulation flags only.**

---

## §8. Tooling + scripts

- **§8.1 make targets** — only `api-check-sync` has <2 internal refs (invoked directly by
  devs/CI, not chained). Not dead. Makefile is lean.
- **§8.2 scripts** — 9 `.sh` unreferenced by Makefile/CI/docs, but all are **cron/manual/
  ops** (false positives per the prompt's own caveat): `cashback-monthly-cron.sh`,
  `seller-payout-daily-cron.sh` (system cron), `install-hooks.sh`, `new-module.sh`
  (manual dev), `disk-hygiene.sh` (ops), and `tool/audit/{check_i18n,dump_schema,
  list_endpoints}.sh` + `tool/normalize-image.sh` (audit/image helpers). **None confirmed dead.**
- **§8.3 workflows** — 7 workflows; all current (deploy.yml added PR #53). No abandoned ones.

**§8 subtotal: 0 confirmed dead.**

---

## §9. Cross-cutting duplicates + discipline drift

### 9.2 Frontend duplicates — confirmed
- **`_LoadingSpinner`** defined identically twice: `lib/features/wallet/plan_detail_screen.dart:341`
  and `lib/features/wallet/wallet_screen.dart:320`. Consolidate to a shared widget. Sev: Low · Eff: S.
- **Error widgets** — a canonical `ErrorBanner` (`lib/core/widgets/error_banner.dart`) coexists
  with ~7 ad-hoc variants: `_ErrorRetry` (×3: my_reviews, my_questions, question_detail),
  `_PaymentErrorBanner`, `_ErrorState`, `_Error`, `AuthErrorBanner`. Consolidation opportunity.
  Sev: Low · Eff: M.

### 9.1 Backend duplicates — none found
Validators (`validateEmail`/`validatePhone`/`validateLocale`) are **centralized** in
`internal/identity/service.go` (single source). No duplicate retry/idempotency/marshal helpers surfaced.

### 9.3 Discipline drift — none measured
Documented patterns (tx-routing #42, user-state-consumer #49) are recent; no drift evidence
in this pass. A targeted re-check belongs in a dedicated discipline-audit, not cleanup.

**§9 subtotal: 2 frontend consolidation findings.**

---

## §10. Severity rollup + cleanup roadmap

### 10.1 Totals (confirmed findings; candidate pools excluded from counts)

| Domain | High | Med | Low | Total | Candidate pools |
|---|---|---|---|---|---|
| Backend Go | ~6 + stub | ~10 | ~6 | ~22 + 41-method stub | — |
| Backend deps | — | — | — | 0 | — |
| Frontend widgets | 6 | ~14 | — | ~20 | 56 classes / 13 providers |
| Frontend deps | — | 2 | 1 | 3 | — |
| Frontend i18n/goldens | — | — | — | 0 | 192 keys / 56 goldens |
| Docs | — | — | 3 | 3 | — |
| Tooling | — | — | 0 | 0 | — |
| Duplicates | — | — | 2 | 2 | — |

### 10.2 Proposed cleanup PRs

1. **`chore/cleanup-backend-dead-symbols`** — §3.1/§3.2/§3.3 (~37 symbols). Mostly XS/S.
   Mechanical. **Recommend simultaneously enabling `unused` in `.golangci.yml`** so it
   can't reaccumulate (the root cause). ~1 session.
2. **`chore/cleanup-frontend-pubspec-deps`** — remove `carousel_slider`, `fl_chart`,
   `json_annotation`. XS, low-risk, high-clarity. ~partial session (fold with #3).
3. **`chore/cleanup-frontend-dead-widgets`** — §5.1: the unadopted `Mopro*` shared widgets
   + the ~14 other credible orphans (30-sec confirm each). Decide `Mopro*`: **adopt or
   delete** (a half-built design system is the misleading-code cost). ~1 session.
4. **`chore/decide-core-impl-stub`** — §3.0 architectural decision (501-stub + gen/core
   server). **Discussion first**, then keep-with-issue or delete. ~1 session.
5. **`chore/cleanup-frontend-duplicates`** — §9.2: shared `LoadingSpinner`; consolidate
   error widgets onto `ErrorBanner`. ~1 session.
6. **`chore/cleanup-docs-accumulation`** — §7: archive old `tool/audit` baselines; REPORT
   link-check; optional CONTRIBUTING consolidation. ~partial session.
7. **(Deferred) i18n + goldens** — §6.2/§6.4 need a usage tool first; do **not** grep-remove.

### 10.3 Prioritization principles
- **High-severity first** (misleading > vestigial): `Mopro*` widgets, exported dead
  funcs, `tracing.Init` (deprecated), `core_impl.go`.
- **Same-domain grouping** for reviewability.
- **Mechanical before architectural** — dead symbols/deps before the `core_impl.go`
  decision and design-system consolidation.
- **No removal PRs during active feature work** in the affected domain.
- **Fix the root cause once:** enabling `unused` in golangci-lint (PR #1) prevents Go
  re-accumulation; a real i18n/golden usage tool prevents grep-guesswork.

### 10.4 Estimated total: **4–5 focused sessions** (excluding the deferred i18n/golden tooling).
