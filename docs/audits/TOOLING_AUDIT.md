# Tooling Audit — 2026-06-03 — Step 3 of the 5-step plan

**Audit-only. No tooling built in this PR.** Findings are scoped into follow-up build PRs (§6).

> **BUILD PROGRESS:**
> - *PR #63 (T3-1 + T3-2):* ✅ **T-003, T-004, T-010, T-001 RESOLVED**; surfaced T-014 + T-015.
> - *T3 cleanup PR:* ✅ **T-014, T-015 RESOLVED** + **T3-sweep-i18n** done (163 dead keys removed).
>   govulncheck is now a required gate; the i18n analyzer reports 0 dead / 0 missing. No new findings.
> - Remaining Step-3 build PRs: **T3-3** bootstrap, **T3-4** migration/discipline linters,
>   **T3-5** Riverpod detector (T-002), **T3-6** nightly/cron (see §6).

## TL;DR
- **MISSING:** 9 (3 HIGH, 5 MED, 1 LOW)
- **EXISTS-AWKWARD:** 2 (`check_i18n.sh` not CI-wired; no `make help`)
- **REDUNDANT:** 0
- **CORRECTED (re-verify caught 2 would-be-false MISSING findings):** golden-diff is **already
  solved** by `golden_platform.dart` (T-013); **rollback automation exists** — `make rollback` →
  `deploy/scripts/rollback.sh`, auto-triggered by `deploy.sh` on health-check failure *and* manual
  (T-012). Both were about to be written up as MISSING before reading the code — the #56/#57 lesson.
- **VERIFIED-COMPLETE sections:** §3.5 deploy (mature via #51–#53), §3.8 ops/backup (backup/restore/disk-watch + grafana-as-code), most of §3.2 build/lint (since #55's `unused` gate).
- **Recommended NOW:** **T-003** (dependency-vuln scanning), **T-010** (wire `check_i18n` into CI — trivial), **T-004** (`make help`), **T-001** (i18n dead-key analyzer — the deferred one that blocks i18n cleanup).

**Honest headline:** the automation surface is **mature** — Steps 1–2 (#54–#61) plus the deploy arc (#50–#53) raised the floor a lot. Backup/restore, Grafana-dashboards-as-code, deploy + image-build, the `make verify` gate (7 golangci linters incl. `unused`, `make deadcode`, integration suites + `-race` + canary-proven wallet gate), golden platform-tagging, git hooks, seed, k6 loadtest, and a module scaffolder **all already exist**. The genuine gaps are concentrated: **no dependency-CVE scanning** (a real security gap for a financial app), **two of the three deferred analyzers** (i18n dead-key, Riverpod inference-shape — the third, golden-diff, turned out solved), and **dev-convenience** (`make help`, `make bootstrap`).

> **Layout note:** the prompt used `app/**`, `app/tool/**`; this repo is `mobile/**` (Flutter),
> `scripts/**`, `tool/**` + `tools/**`, `cmd/**`, `.github/workflows/**`, `deploy/**`. No
> `.vscode/`/`.idea/` in tree. All paths below are the real ones.

## Methodology (§2 discipline, carried from #54–#61)
- **CONFIRMED** = re-verified on this branch (`main@cfada085`) with the command shown inline.
- **PROBABLE** = structure suggests it, not reproduced. **UNKNOWN** = flagged, insufficient signal.
- Before flagging a script REDUNDANT, audited in-tree + `docs/` + `.github/` + cron references
  (the PR #56 cron lesson). Before flagging anything MISSING, **read the existing code** (the PR
  #57 lesson) — and it paid off four times: `check_i18n.sh`/`list_providers.dart`/`golden_platform.dart`
  each partially address a "deferred" analyzer (changing three classifications, one to EXISTS-FINE),
  and reading the `make rollback` target body refuted a from-memory MISSING (§2.2 hidden-invocation
  audit). Memory is a hypothesis; the branch is the evidence.
- Documented designs (CLAUDE.md / CONTRIBUTING / retired-decisions) are not findings.

---

## §3.1 CI / workflow findings

8 workflows (`ls .github/workflows/`): `branch-guard`, `build-images`, `deploy`, `e2e`,
`flutter-ci`, `golden-rebaseline`, `make-verify`, `openapi-ci`. Triggers:
```
$ for w in .github/workflows/*.yml; do echo "$(basename $w): $(grep -oE 'pull_request|workflow_dispatch|schedule|push' $w | sort -u | tr '\n' ,)"; done
branch-guard: pull_request,   build-images: push,workflow_dispatch,   deploy: push,workflow_dispatch,
e2e: pull_request,push,workflow_dispatch,   flutter-ci: pull_request,push,   golden-rebaseline: push,workflow_dispatch,
make-verify: pull_request,push,   openapi-ci: pull_request,push,
```
`make-verify` is the gate (required check, PR #50); `flutter-ci`/`openapi-ci`/`e2e` add Flutter,
generated-sync, and staging-smoke coverage. No overlap/redundancy found. **Mostly healthy** — two gaps:

### T-003 — no dependency-vulnerability scanning
**✅ RESOLVED (T3-1) — was MISSING/HIGH/NOW.** Added `.github/workflows/govulncheck.yml`
+ `.github/dependabot.yml` (gomod/actions/pub) + `make govulncheck`. The scan surfaced
**2 called stdlib vulns → new finding T-014**; the workflow is `continue-on-error` until
T-014 lands, then it becomes a required gate.
**Original status: MISSING | Severity: HIGH | Confidence: CONFIRMED | Priority: NOW**
```
$ ls .github/dependabot.yml 2>/dev/null            → (none)
$ git grep -lniE 'govulncheck|trivy|osv-scanner|snyk|nancy' -- .github/ Makefile  → (no matches)
```
No automated CVE scanning of Go modules, Dart packages, or base images. `gosec` (in the
golangci gate) catches *code* patterns but **not** known-vulnerable dependencies. For a
financial app handling PII + payments, this is a real security-hygiene gap.
Recommendation: a `security.yml` workflow running `govulncheck ./...` + Dart `dart pub
outdated`/audit + (optionally) `trivy` on the built images; + `.github/dependabot.yml` for
Go modules / GitHub Actions / pub. Small (~60-line workflow + dependabot config), purely additive.

### T-009 — no scheduled (nightly) workflows
**Status: MISSING | Severity: MED | Confidence: CONFIRMED | Priority: SOON**
```
$ git grep -lnE 'schedule:|cron:|merge_group' -- .github/workflows/   → (no matches)
```
Every workflow is PR/push/dispatch-triggered; nothing runs on a schedule. The TESTING_AUDIT
deferred a **×50 `-race` repro** and **soak** to "a nightly job that doesn't exist." A nightly
`schedule:` workflow could host: the ×50 `-race` storage stress, the F-002 stub watch, T-003's
vuln scan (re-run daily), and a longer e2e soak. Recommendation: one `nightly.yml` with a
`schedule:` cron. ~80 LOC. (Also flags **merge_group**: no workflow triggers on it, so an
eventual merge-queue would not re-run gates — PROBABLE-LOW, PARK until a queue is adopted.)

**Considered, NOT a finding — generalizing the #61 wallet-gate canary.** §3.1 asks whether other
integration suites need the #61 "deliberately-failing test proves the gate runs" pattern.
`git grep -lnE 'Canary|gatecanary' -- '**/*_test.go'` → none (the #61 canary was removed by
design — you don't keep a failing test). The real #61 bug was a one-off (`property-ledger` ran
`-run Property`, skipping 9 wallet tests); it's closed now that `integration-wallet` exists. A
standing "verify every gate actually executes its tests" meta-tool is over-engineering for an
8-target Makefile — no T-ID (the anti-padding rule, §2.3). Re-evaluate if the target count grows.

---

## §3.2 Build / test / lint findings

`make verify` is the canonical gate (`grep '^verify:' Makefile`): fmt, vet, `test` (`go test
-race ./...`), `lint` (golangci-lint), boundaries, property-{cashback,payout,ledger,timex,order},
integration-{e2e,cart,identity,identity-race,payment,wallet}, verify-image-manifest,
verify-contrast. golangci enables **depguard, gocyclo, errcheck, revive, gosec, gocritic,
unused** (`.golangci.yml`); `make deadcode` is the on-demand whole-program scan. **This is
mature** (raised across #55/#58/#61) → VERIFIED-COMPLETE for the core gate. Two friction findings:

### T-004 — no `make help`; no `##` self-documenting targets
**✅ RESOLVED (T3-1) — was EXISTS-AWKWARD/MED/NOW.** Added a `help` target +
`.DEFAULT_GOAL := help` (bare `make` now prints help) + `## ` annotations on 31
developer-facing targets.
**Original status: EXISTS-AWKWARD | Severity: MED | Confidence: CONFIRMED | Priority: NOW (trivial)**
_(The Makefile exists and works; its 64-target interface is friction-heavy to navigate — AWKWARD, not MISSING.)_
```
$ grep -cE '^[a-z][a-z0-9_-]*:' Makefile     → 64 targets
$ grep -cE '^help:' Makefile                 → 0
$ grep -cE '^[a-z][a-z0-9_-]*:.*##' Makefile → 0   (no inline target docs)
```
64 targets, no `make help`, no `## description` annotations. A contributor must read the
~500-line Makefile to find the right command. Recommendation: add `## comment` to each
public-facing target + a 3-line `help:` target (the standard `awk` one-liner). ~40 LOC, no risk.

### T-010 — `check_i18n.sh` exists but is not CI-wired (translation completeness ungated)
**✅ RESOLVED (T3-1) — was EXISTS-AWKWARD/MED/NOW.** Added a `--strict` mode (fails on
EXTRA keys only — missing keys are by-design for unlaunched markets) + `make i18n-check` +
a flutter-ci job. Canary-proven. **Not** superseded by T-001 (completeness ≠ usage — both run).
**Original status: EXISTS-AWKWARD | Severity: MED | Confidence: CONFIRMED | Priority: NOW (trivial)**
```
$ git grep -rn 'check_i18n' -- .github/ Makefile docs/   → (no matches — manual only)
```
`tool/audit/check_i18n.sh` is a solid translation-**completeness** checker (flattens locale
JSONs, diffs each against the `tr-TR` master for missing/extra keys), but it runs on no gate —
a locale can silently drift incomplete. Recommendation: a `make i18n-check` target + a line in
`flutter-ci.yml` failing the PR on missing master keys. ~15 LOC. **Note:** completeness ≠ the
dead-key *usage* analyzer (that's T-001 — different problem).

---

## §3.3 Migration findings

`cmd/migrate-tool/main.go` runs migrations; the `pg-ledger-test-up` target spins a **fresh**
`postgres:16-alpine` and applies init + `migrations/ledger/*.up.sql` in order on every
integration run (so migrations ARE gated against a clean DB in CI). Reversibility exists too:
```
$ ls migrations/ledger/ | grep -cE '\.up\.sql$'   → 7
$ ls migrations/ledger/ | grep -cE '\.down\.sql$' → 7   (paired up/down — not forward-only)
```
Running + ordering + reversible pairs + fresh-DB CI application all **EXIST-FINE**. The gaps are
*safety-linting* and *scaffolding*, not the runner:

### T-006 — no migration linter (destructive-change / lock-duration guard)
**Status: MISSING | Severity: MED | Confidence: CONFIRMED | Priority: SOON**
```
$ git grep -lniE 'new.migration|migration.lint|DROP COLUMN' -- scripts/ tool/ Makefile
  → only docs (legal_copy_baseline.md, tranche4b_blockers.md) — no linter script
```
The TESTING_AUDIT §3.8 flagged migration-safety as UNKNOWN/not-audited. There's no automated
check for `DROP COLUMN`/`DROP TABLE` without a soft-deprecation window, `ALTER … ` without
`CONCURRENTLY`, or single-transaction backfills (lock-duration risk). Recommendation: a
`scripts/lint-migrations.sh` (grep-based, with allow-list comments) gated in CI. ~120 LOC.

### T-011 — no new-migration generator
**Status: MISSING | Severity: LOW | Confidence: CONFIRMED | Priority: LATER**
`scripts/new-module.sh` scaffolds a new internal module (the 5-file stub), but there's no
equivalent `new-migration.sh` (timestamped up/down pair + template). Low — migrations are
infrequent and the naming convention is simple. Recommendation: a tiny scaffolder when migration
churn justifies it.

---

## §3.4 Job / cron findings

The production crons exist + are version-controlled: `scripts/cashback-monthly-cron.sh`,
`scripts/seller-payout-daily-cron.sh`, `scripts/disk-hygiene.sh` (deployed via host crontab;
the F-002/#56 lesson — these are EXISTS-FINE, not redundant). A `backup-cron-health` Grafana
dashboard monitors them. Gap:

### T-008 — no local cron dry-run / overlap simulator
**Status: MISSING | Severity: MED | Confidence: CONFIRMED | Priority: SOON**
The TESTING_AUDIT §5.4 asked whether the financial crons are covered by cron-overlap simulation;
they aren't (the cron *scripts* are thin wrappers around the `mopro` CLI; the idempotency is
tested at the engine level, but there's no tool to dry-run a cron locally with seeded data or to
fire two overlapping invocations and assert exactly-once). Recommendation: a `make cron-dryrun
CRON=cashback-monthly` against the seed DB + an overlap test. ~150 LOC. (Engine idempotency is
already covered by the cashback/payout property suites — this is about the cron *wrapper* + overlap.)

---

## §3.5 Deploy findings — VERIFIED-COMPLETE

`deploy.yml` (PR #53: `workflow_dispatch` SSH deploy, `verify_only` default, concurrency-
serialized, `tool/audit/deploy_script.sh` with compose-dir discovery), `build-images.yml`
(GHCR push, `IMAGE_NS` parameterized #51/#52), and the `e2e.yml` staging smoke form a mature
deploy surface. Pre-deploy verification was hardened through #53 + the #61 canary discipline.
**Verified:** `ls .github/workflows/{deploy,build-images,e2e}.yml` all present; `make verify`
is the merge gate. **No gaps** — including rollback (see T-012):

### T-012 — rollback automation — ✅ CORRECTED to EXISTS-FINE (nearly a false MISSING)
**Status: EXISTS-FINE | Confidence: CONFIRMED**
```
$ awk '/^rollback:/{f=1} f{print} f&&/^$/{exit}' Makefile
  rollback:
  	SERVER=$(SERVER) SSH_PORT=$(SSH_PORT) ./deploy/scripts/rollback.sh
$ sed -n '1,5p' deploy/scripts/rollback.sh
  # deploy/scripts/rollback.sh — Restore previous image set on Mopro VDS.
  # Called automatically by deploy.sh on health check failure, or manually.   set -euo pipefail
$ git grep -ln rollback -- deploy/ docs/  → deploy/RUNBOOK.md, deploy/scripts/deploy.sh,
                                            docs/launch/L10-production-cutover-plan.md, runbooks…
```
Rollback automation **exists and is well-integrated**: `make rollback` →
`deploy/scripts/rollback.sh` (executable, `set -euo pipefail`), **auto-triggered by `deploy.sh`
on health-check failure** as well as manual, and documented in RUNBOOK + the production-cutover
plan + runbooks. This was about to be written up as MISSING/PARK from memory; reading the target
body (the §2.2 hidden-invocation audit) refuted it. **Not a gap.** Post-deploy health
verification is likewise present (deploy.sh runs the health check that triggers the auto-rollback).

---

## §3.6 Static analysis findings (the deferred-analyzer trio + adjacent)

The three "deferred analyzers" were re-examined by **reading the existing scripts** — and the
classification changed for all three:

### T-001 — i18n dead-key usage analyzer (prefix-aware) — MISSING
**✅ RESOLVED (T3-2) — was MISSING/HIGH/NOW.** Built `tool/audit/check_i18n_usage.dart`
(zero-dep text-based Dart, not AST — see `docs/internal/i18n-analyzer.md` for the named
deviation) + 13 self-tests + dual baselines + flutter-ci gate. Found 163 dead + **10 missing
keys → new finding T-015**. The dead-key **sweep** is a separate follow-up PR (this PR builds
the gate, not the cleanup).
**Original status: MISSING | Severity: HIGH | Confidence: CONFIRMED | Priority: NOW**
```
$ sed -n '1,20p' tool/audit/check_i18n.sh   → "Audit translation COMPLETENESS … diffs every locale against the master"
```
`check_i18n.sh` checks *completeness* (missing/extra keys per locale), **not** *usage* — it
can't tell whether a key is referenced in code, because easy_localization builds keys via
prefix concatenation (`'profile.'.tr()` + interpolation) that defeats grep. The CLEANUP_AUDIT
(#54) + #56 explicitly deferred the **dead-key** analyzer; it's still missing. Recommendation:
a Dart static analyzer that resolves prefix/interpolation to a `key → file:line` usage manifest,
gated to fail on dead keys. ~400–700 LOC Dart + a `flutter-i18n-usage` step. No prerequisites.

### T-002 — Riverpod inference-shape detector — MISSING
**Status: MISSING | Severity: HIGH | Confidence: CONFIRMED | Priority: SOON**
```
$ sed -n '1,15p' tool/audit/list_providers.dart  → "Inventory every Riverpod provider … name, file:line, provider kind"
```
`list_providers.dart` *inventories* providers + Notifier subclasses, but doesn't flag
inference-typed providers or classify each by the three documented Notifier shapes (#1 const-then-
event, #2 microtask-defer, #3 post-await mutation). The shape-drift detector the CLEANUP/TESTING
audits wanted is still missing. Dev-dep check (grounds the build approach):
```
$ grep -nE 'custom_lint|very_good_analysis|riverpod_lint' mobile/pubspec.yaml
  47:  very_good_analysis: ^6.0.0       # a lint ruleset — NOT a custom_lint plugin host
```
`very_good_analysis` is present but it's a rule *config*, not a `custom_lint` host, and
`custom_lint`/`riverpod_lint` are **not** deps — so the cheapest path is to **extend the existing
standalone `list_providers.dart`** (add shape classification + inference flagging) rather than
introduce a new `custom_lint` toolchain. ~300–500 LOC. Builds on the existing lister.

### T-013 — golden platform-aware diff — ✅ CORRECTED to EXISTS-FINE (deferral resolved)
**Status: EXISTS-FINE | Confidence: CONFIRMED**
```
$ sed -n '1,18p' mobile/test/_support/golden_platform.dart
  → "Platform-mismatch guard … each golden gets a sidecar <name>.png.meta recording the platform …
     on compare: if sidecar platform != current OS, fail with a clear message pointing at make
     update-goldens (instead of a cryptic pixel diff)"
```
The "noisy local cross-platform diff" problem the trio's third item described is **already
solved** by `golden_platform.dart` (+ `golden-rebaseline.yml` for Linux re-baselining): it
fails fast with guidance on a platform mismatch rather than emitting platform-artifact pixel
noise. **Not missing** — likely added (Session 4e) after the original deferral. Removed from the
build queue.

### Adjacent: discipline-pattern linters
### T-007 — no linter for the recurring discipline patterns
**Status: MISSING | Severity: MED | Confidence: CONFIRMED | Priority: SOON**
```
$ git grep -lniE 'pool.*acquire.*tx|StatusDeleted|FOR UPDATE SKIP LOCKED' -- scripts/ tool/
  → only tool/audit/identity_user_state_consumers.md (a PR #49 manual-audit DOC, not a script)
```
The patterns repeatedly hand-audited across the arc — pool-acquire-inside-tx (#42/#47),
soft-deleted-user-consumer missing `Status == StatusDeleted` (#49), storage-idempotency UNIQUE
presence — have **no automated linter**; each was a manual grep. `check-module-boundaries.sh` +
depguard cover cross-module imports, but not these. Recommendation: a `scripts/lint-discipline.sh`
(grep/AST heuristics, allow-list comments) gated in CI, so the audits don't have to re-grep by
hand. ~200 LOC. (Heuristic → expect false positives; design with `//lint:ok` escape comments.)

---

## §3.7 Dev convenience findings

### T-005 — no `make bootstrap` / one-command local setup
**Status: MISSING | Severity: MED | Confidence: CONFIRMED | Priority: SOON**
```
$ grep -nE '^(bootstrap|setup|dev):' Makefile   → (none; only grafana-deploy etc.)
```
No single target installs Go/Flutter deps, runs codegen, brings up the dev DB, and seeds it. A
new contributor must assemble the steps from CONTRIBUTING + the Makefile. Hooks install is
manual (`make hooks` / `scripts/install-hooks.sh`). Recommendation: `make bootstrap` chaining
deps + `api-gen` + `pg-ledger-test-up` + seed + hooks. ~50 LOC, high onboarding leverage.

**EXISTS-FINE (verified):** seed tooling (`scripts/seed/cmd/seed` + data + `make build-seed/
seed-dry-run/seed-staging/seed-prod`), git hooks (`.githooks/` + `tool/setup-hooks.sh` + `make
hooks`), module scaffolder (`scripts/new-module.sh`), k6 loadtest (`scripts/loadtest/k6-smoke.js`
+ `make loadtest`), local mocks/stubs (`mobile/test/_support/*stub*.dart`).

---

## §3.8 Ops / runbook findings — VERIFIED-COMPLETE

```
$ ls scripts/                → backup.sh, restore-drill.sh, disk-watch.sh, disk-hygiene.sh, smoke/run.sh …
$ find deploy/grafana/dashboards -name '*.json'  → backup-cron-health.json, financial-health.json, infra-health.json
$ grep -n '^grafana-deploy:' Makefile  → present
```
Backup (`backup.sh`), restore drill (`restore-drill.sh`), disk monitoring (`disk-watch.sh` +
`disk-hygiene.sh`), smoke (`scripts/smoke/run.sh` + `manual-handoff.md`), and **Grafana
dashboards-as-code** (3 dashboards + `make grafana-deploy`) all exist. The SSH-wrapper concern
from #53 is covered by `deploy.yml` + `deploy_script.sh`. **Healthier than the prompt assumed —
no ops-automation gap.** (Capacity tooling is dashboard-based, which is appropriate.)

---

## §4 Cross-cutting findings

- **§4.1 Consistency — mostly good.** `make X` is the canonical entry; **15 of 18** shell scripts
  use `set -euo pipefail` (`git grep -l 'set -euo pipefail' -- 'scripts/*.sh' 'tool/**/*.sh' | wc -l`).
  Invocation is a consistent `make` → script/`go run`/`dart run` layering. No finding (the 3
  un-`pipefail`'d scripts are a LOW-PARK tidy-up, not worth a T-ID).
- **§4.2 Documentation — the `make help` gap (T-004).** CONTRIBUTING explains patterns but
  there's no single "all dev commands" page; `make help` (T-004) would be that page.
- **§4.3 Onboarding gap.** Day-1 blockers: no `make bootstrap` (T-005), no `make help` (T-004),
  manual hook install. First-hour friction is real; the rest of the surface (seed, hooks, gate)
  is good once discovered. T-004 + T-005 close most of the onboarding gap cheaply.

## §5 Verified-complete categories (evidence above)
- **§3.5 Deploy** (deploy.yml/build-images/e2e; mature #50–#53) — incl. rollback (T-012, EXISTS-FINE).
- **§3.8 Ops/backup** (backup/restore/disk + grafana-as-code).
- **§3.2 build/lint core** (`make verify`, 7 golangci linters + `unused`, `make deadcode`).
- **Golden infra** (`golden_platform.dart` + `golden-rebaseline.yml` — T-013 resolved).
- Hooks, seed, loadtest, module scaffolder, audit-regen (`make audit`/`audit-test`).

---

## §6 Recommended build sequence

NOW findings first (small + high-leverage), then SOON grouped by area. LATER/PARK listed unsequenced.

### PR T3-1 — `chore/tooling-ci-hygiene` (NOW) — closes T-003, T-010, T-004
- Add `security.yml` (govulncheck + dart audit) + `.github/dependabot.yml` (T-003).
- `make i18n-check` target + `flutter-ci` step wiring the existing `check_i18n.sh` (T-010).
- `make help` + `##` target annotations (T-004).
- Size: ~150 LOC (workflows + Makefile). No prerequisites. Highest value/effort ratio.

### PR T3-2 — `feat/i18n-deadkey-analyzer` (NOW) — closes T-001
- Dart prefix/interpolation-aware key-usage analyzer → manifest + CI gate.
- Size: ~400–700 LOC Dart. No prerequisites. **Split-bailout** if prefix resolution balloons:
  ship the manifest generator first, the CI-fail gate second.

### PR T3-3 — `feat/dev-bootstrap` (SOON) — closes T-005
- `make bootstrap` (deps + api-gen + dev DB + seed + hooks). ~50 LOC. Builds on existing targets.

### PR T3-4 — `feat/migration-and-discipline-linters` (SOON) — closes T-006, T-007
- `scripts/lint-migrations.sh` (destructive/lock-duration) + `scripts/lint-discipline.sh`
  (pool-in-tx / soft-delete-consumer / idempotency), both CI-gated with allow-list escapes.
- Size: ~320 LOC. Heuristic → budget for false-positive tuning. **Split** the two scripts if either
  needs heavy tuning.

### PR T3-5 — `feat/riverpod-shape-detector` (SOON) — closes T-002
- Extend `list_providers.dart` to classify the 3 Notifier shapes + flag inference. ~300–500 LOC.
- Prereq: confirm whether `custom_lint` is a dev-dep (cheaper as a lint plugin if so).

### PR T3-6 — `feat/nightly-and-cron-tooling` (SOON) — closes T-009, T-008
- `nightly.yml` (`schedule:`) hosting ×50 `-race` repro + vuln re-scan + soak; `make cron-dryrun`
  + overlap test. ~230 LOC.

### LATER / PARK (write-up only, unsequenced)
- **T-011** new-migration generator (LOW, when migration churn justifies).
- **merge_group** workflow support (LOW, PARK until a merge queue is adopted).
- 3 shell scripts lacking `set -euo pipefail` (LOW, tidy-up; no T-ID — see §4.1).
- (T-012 rollback + T-013 golden-diff are **resolved/EXISTS-FINE** — nothing to build.)

**Total to clear NOW+SOON:** ~6 follow-up PRs, ~1450 LOC, dominated by the two analyzers (T-001, T-002).
NOW alone (T3-1 + T3-2) closes the security gap + the highest-leverage dev-convenience + the
deferred i18n analyzer in ~2 small PRs.

---

## New findings (surfaced during the T3-1 + T3-2 build)

### T-014 — Go stdlib vulnerabilities (govulncheck)
**✅ RESOLVED (T3 cleanup) — was MISSING-FIX/MED/NOW.** Bumped go.mod + go.work to **1.25.11** +
Dockerfile (`golang:1.25.11-alpine`) + centralized the workflow pins (`openapi-ci` 1.22 →
go-version-file); removed `continue-on-error` → govulncheck is now a **required** gate. **Correction:**
the "1.26.4" below was a local-1.26.3 artifact; the authoritative CI scan (go 1.25) showed **9 called
vulns**, all fixed by the same-minor patch **1.25.11** (Go backports security fixes). Verified
`GOTOOLCHAIN=go1.25.11 govulncheck ./...` → "No vulnerabilities found".
**Original status: MISSING-FIX | Severity: MED | Confidence: CONFIRMED | Priority: NOW**
Surfaced by the T-003 scan (`govulncheck ./...`, real exit 3):
```
Vulnerability #1: GO-2026-5039  Standard library  net/textproto@go1.26.3  → fixed in go1.26.4
Vulnerability #2: GO-2026-5037  Standard library  crypto/x509@go1.26.3    → fixed in go1.26.4
(+ 1 import-only vuln NOT called by our code)
```
Both are **called** stdlib vulns, fixed by a single Go-toolchain bump (1.26.4+). Filed as one
finding (shared remediation). `crypto/x509` is security-relevant (cert handling). Recommendation:
a focused PR bumping the `go` directive / CI toolchain to 1.26.4+, then remove `continue-on-error`
from `govulncheck.yml` to make it a required gate. Per §8 this PR surfaces + tracks, does not patch.

### T-015 — 10 i18n keys referenced in code but missing from the tr-TR master
**✅ RESOLVED (T3 cleanup) — was MISSING-FIX/MED/SOON.** Added all 10 to tr-TR (master) + en-US with
sibling-key translations (no TRANSLATION_NEEDED — every key was unambiguous from call-site context +
existing siblings); de/ar left partial (future markets). `make i18n-usage` → 0 missing; baseline cleared.
**Original status: MISSING-FIX | Severity: MED | Confidence: CONFIRMED | Priority: SOON**
Surfaced by the T-001 analyzer (`check_i18n_usage.dart --manifest`):
```
checkout.cancel_payment_body/_title, checkout.payment_3ds(/_subtitle),
checkout.payment_bank_transfer, checkout.payment_cashback, checkout.payment_coming_soon,
checkout.secure_payment_body/_title, common.yes
```
Real bug: these are called via `'…'.tr()` (e.g. `checkout_payment_screen.dart`) but absent from
`tr-TR.json` (the launched locale) **and** `en-US.json`, so the TR app renders the raw key string.
Frozen in `tool/audit/i18n_missing_baseline.txt` (ratcheted). Recommendation: a translation-fix PR
adds the Turkish (+ other-locale) strings and clears the baseline. Content work → out of scope for
the gate PR (§8).
