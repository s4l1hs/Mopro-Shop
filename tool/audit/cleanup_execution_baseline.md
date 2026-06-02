# Cleanup Execution — Re-verification Baseline + CoreServer Decision

Branch `chore/project-cleanup-confirmed`, base `main@90d3e661` (PR #54 merged).
Executes the **confirmed** half of `CLEANUP_AUDIT.md`. Candidate-pool items
(i18n keys, goldens, Riverpod inference classes) are deliberately **out of scope**.

## Re-verification (all audit findings re-confirmed at PR time)

Re-ran the audit's tools on fresh `main@90d3e661`; output is **byte-identical** to the
audit's committed raw evidence → no interim merge invalidated any finding.

- `deadcode -test ./...` (excl `web/node_modules`, a non-tracked false positive): **73**
  = 41 in `internal/api/core_impl.go` + **32 real**. IDENTICAL to audit.
- `staticcheck -checks=U1000 ./...`: **10**. IDENTICAL to audit.
- Frontend `Mopro*` widgets — re-verified 0 external refs (`rg -w`, lib/+test/):
  `MoproButton`, `MoproInput`, `MoproChip`+`MoproChoiceGroup`, `MoproSheet`,
  `PriceDisplay`, `MoproAppBar`. **Siblings kept (live):** `MoproBadge` (1),
  `SkeletonBox` (2), `StarRating` (1), `ThemeToggle` (2). **Scope note:** the audit/
  prompt named 3 (`MoproButton`/`MoproInput`/`PriceDisplay`); re-verification confirms
  the full `mopro_*` set is equally dead, so all 6 files are removed (leaving half an
  unadopted widget set would be incoherent). Each independently 0-ref.
- pubspec: `carousel_slider`, `fl_chart`, `json_annotation` — 0 `package:` imports in
  lib/+test/. `json_annotation` codegen-safe: 0 `@JsonSerializable`/`@JsonKey`, 0
  `.g.dart` in `mobile/lib/`. `cupertino_icons` kept (implicit icon font — false positive).
- `_LoadingSpinner` (wallet `plan_detail_screen.dart` vs `wallet_screen.dart`): the two
  are **byte-identical** → safe behavior-preserving consolidation.

**No findings dropped** — all re-confirmed dead. No new callers appeared.

## Baselines
- Go non-test LOC: 42,143 · Dart lib LOC: 35,875.
- `golangci-lint run` (current config): **0 findings** — confirms the current config
  does NOT catch dead code (the root cause this PR fixes).
- `make verify`: green on main (~9 min CI).

## CoreServer 501-stub decision (§2.4 AskUserQuestion) → **Option B: Abandoned path**

Context that informed it: `core_impl.go` (added 2026-05-29, session-3) is the **only**
importer of the generated `gen/core` server interface; its sibling `fin_impl.go`/
`FinServer` **is** wired (deadcode did not flag it). So the oapi-codegen strict-server
pattern was adopted for fin-svc but **never for core-svc** (which uses the stdlib mux in
`cmd/core-svc/main.go`). `gen/core` is regenerated from `api/openapi.yaml` by
`openapi-ci.yml` regardless, so deleting `core_impl.go` is clean (no implementer, but the
generated types still regenerate).

**Decision: delete `internal/api/core_impl.go` + add a CONTRIBUTING "Architectural
decisions retired" note** recording that core-svc HTTP is deliberately the stdlib mux,
not the gen/core StrictServerInterface — so nobody recreates the dead stub.

## Structural fix (root cause)
Enable golangci-lint `unused` (catches the **unexported** dead class — recurrence guard).
**Note:** golangci-lint v2 `unused` treats *exported* library symbols as used-externally,
so it will NOT catch exported-unreachable code (most of the 32 deadcode findings). The
complete recurrence guard therefore also adds a `deadcode` step to `make verify`
(`deadcode -test ./cmd/... ./internal/... ./pkg/...`) — wired only if green post-cleanup.
