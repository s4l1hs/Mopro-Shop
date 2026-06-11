# Stabilize Main — diagnosis & fix

Main was "merged but not green" after #182–#185. This enumerates every non-green
signal on `main` HEAD (`df5d3502`), required vs informational, with root cause.

## Diagnosis (authoritative, from the GitHub API on `df5d3502`)

**All 13 check-runs are green** — including the ones the task suspected:

| Check | Required? | Result |
|---|---|---|
| verify, flutter analyze, flutter test, build_runner, dart analyze (mopro_api), i18n completeness, i18n dead-key, riverpod, govulncheck, build (core/fin/jobs-svc) | required (most) | ✅ success |
| **flutter golden (informational)** | informational | ✅ **success** |

Two suspicions in the brief did **not** hold (discovery shifts):
- **Informational golden is GREEN.** #184 changed `order_detail_screen` /
  `account_screen` / `return_detail_screen` but those edits (a reorder button wired
  behind existing layout, a Help `onPressed`, a returns timeline) did not move any
  covered golden's pixels — the golden job passed on HEAD. **No rebaseline needed.**
- **The coupon `0092` DDL residual is already fixed.** #185 synced both hand-rolled
  orders DDLs; `verify` is green on HEAD. No residual 42703.

**The one real red: the `nightly-soak` workflow.** The commit's check-**suites**
show 1 `github-actions` failure — `nightly-soak` — with `event=push`,
`conclusion=failure`, **0 jobs** (a *startup_failure*: "This run likely failed
because of a workflow file issue"). It is **not** a required context and **not** a
PR check (it triggers only on `schedule` + `workflow_dispatch`), so it never gates a
merge — but GitHub surfaces the broken-workflow startup_failure as a run **on every
push to any branch**, so every commit (incl. main HEAD) carries a red ❌ check-suite.
That is the "not green".

It is **long-standing, not from #182–185**: it has startup-failed on *every* push
since `nightly.yml` was added (`b784f3b5`, 2026-06-03). The merge batch just drew
attention to it.

The combined **legacy commit-status** is `pending`, but that is an empty-list
artifact (there are **zero** legacy statuses on the commit — everything is a modern
check-run), not a red.

## Root cause (nightly.yml)

The `Open issue on failure` step's `gh issue create --body "…"` used a multi-line
double-quoted shell string inside a `run: |` block scalar, and its second line —
`Run: ${{ … }}` — sat at **column 0**, below the block-scalar indent (10 spaces).
YAML therefore *ended the block scalar* at the blank line and parsed `Run:` as a
**top-level workflow key** → GitHub's Actions schema rejects it
(`unexpected key "Run" for "workflow" section`, via actionlint) → startup_failure.
Plain YAML parsers accept it (it's a valid mapping with an extra key), which is why
it passed a naive `yaml.safe_load` and went unnoticed.

## Fix

Collapse the `--body` to a **single line** (no embedded newline → no continuation
line → no block-scalar-indent hazard). `actionlint` is clean on the result, and a
syntax-check sweep of all `.github/workflows/*.yml` finds no other
startup-failure-class issues.

## Net
- main HEAD: 13/13 check-runs green; the nightly startup_failure is removed at the
  source → no more red check-suite on every push.
- Lesson (also `CUTOVER_LEDGER §5`): the #182 coupon merge went in with a red
  `verify` via the `enforce_admins=false` admin override, which is what let the e2e
  DDL regression (#185) reach main — the override is for confirmed flakes only.
