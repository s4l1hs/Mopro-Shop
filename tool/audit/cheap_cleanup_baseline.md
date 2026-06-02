# Cheap Cleanup Follow-up — Re-verification Baseline

Branch `chore/cleanup-cheap-followup`, base `main@2261595e` (PR #55 merged).
Targets the cheap remainder of `CLEANUP_AUDIT.md` §7 (docs), §8 (tooling), §9
(`var _ =` pattern + post-linter duplicates). **Outcome: nothing actionable to
remove** — every candidate re-verifies as a false positive or already-done. This
PR therefore ships the re-verification record + CONTRIBUTING discipline + roadmap
status, not removals. (Per PR #55's lesson, re-verification at PR time is exactly
the point — and here it confirms the audit's own "0 rot / 0 confirmed dead" calls.)

## §2.3 — `var _ = f` suppression sweep → ZERO instances
`rg '^\s*var _ = ' --type go` (prod + test) → **no matches.** PR #55 removed the
only one (`reconcile` buildCheck1/2DedupKey). It was a single occurrence, not a
recurring pattern. Interface-satisfaction assertions (`var _ Iface = (*T)(nil)`,
e.g. `fin_impl.go`) are a different, legitimate form (typed; not a dead-code mask)
and are out of scope. **Nothing to sweep.**

## §2.4 — post-linter `unused` findings → ZERO
`golangci-lint run ./...` → 0 `(unused)` findings. The gate enabled in PR #55 is
holding; no dead Go code has accumulated. **§6 skipped.**

## §2.1 — Documentation (CLEANUP_AUDIT §7 said "0 rot; accumulation only")
Re-verified — confirmed, plus checked for NEW staleness from PR #55's removals:
- CONTRIBUTING.md references to `core_impl`/`CoreServer` (lines ~816-825) and
  `RefreshWorker` (~597) are the **correct** notes I wrote in PR #55 — the
  "Architectural decisions retired" entry (CoreServer deleted) and the
  cleanup-execution lessons (RefreshWorker kept as a build-tag FP). Accurate, not
  stale. No edit needed.
- No doc presents a PR-#55-removed symbol (`MoproButton`/`PriceDisplay`/
  `tracing.Init`/`NewNoopDLQRepository`/`carousel_slider`/`fl_chart`) as live.
- Deploy docs current (refreshed across PRs #51-#53; IMAGE_NS, GHCR, deploy.yml).
- REPORT.md: historical per-PR record; entries describing later-removed code are
  not "factually wrong" (they describe past work). No history rewrite. No broken
  current-state ref found.
- `tool/audit/*.md` baselines: historical traceability artifacts; retained by
  design. The RefreshWorker/Sign* reclassification is already recorded in
  CLEANUP_AUDIT.md's execution-status banner (PR #55). No baseline is from a
  reverted PR, so none deleted.
**Documentation: nothing to fix.**

## §2.2 — Tooling (CLEANUP_AUDIT §8 said "0 confirmed dead")
Re-verified — confirmed:
- **make target `api-check-sync`** (Makefile:332): runs
  `git diff --exit-code internal/api/gen/ mobile/packages/mopro_api/` — a
  **developer convenience** mirroring what `openapi-ci.yml` enforces inline
  (line 63). Not chained by other targets, but a legitimate local entry point
  (like `make api-gen`). **Keep.**
- **9 "unreferenced" scripts** — all cron/manual/ops, invoked outside repo
  visibility (host crontab / dev workflow):
  - `scripts/cashback-monthly-cron.sh`, `scripts/seller-payout-daily-cron.sh` —
    **production financial crons** (CLAUDE.md §4.7/§4.8: 02:00/02:30 UTC;
    docs/ops/healthchecks.md). Removing them breaks prod. **KEEP (critical).**
  - `scripts/install-hooks.sh`, `scripts/new-module.sh` — manual dev tooling.
  - `scripts/disk-hygiene.sh` — host ops.
  - `tool/audit/{check_i18n,dump_schema,list_endpoints}.sh`, `tool/normalize-image.sh`
    — audit/image helpers run on demand.
  All **keep** — "no Makefile/CI/doc reference" ≠ dead for cron/manual scripts
  (the audit's own caveat; PR #55's build-tag lesson generalizes: absence of a
  static reference is not absence of a consumer).
- **Workflows** (`.github/workflows/`): 7, all current (deploy.yml added #53). None abandoned.
**Tooling: nothing to remove.**

## §1.6 escape hatches — not triggered
No fundamental code↔doc contradiction; no `var _ =` protecting live code (there are none).

## Net
Removals: **0**. The cheap-cleanup candidates were already false positives
(intentional cron/dev/manual) in the audit, or resolved in PR #55 (`var _ =`), or
accumulation-by-design (audit baselines). Value delivered: this record (so the
next cleanup pass doesn't re-chase these), the CONTRIBUTING discipline notes, and
roadmap status. Remaining real work is **tooling-blocked** (i18n / goldens /
Riverpod inference — need usage-aware analyzers), tracked in CLEANUP_AUDIT §10.
