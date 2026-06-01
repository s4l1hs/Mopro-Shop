# Stack Drain State — `chore/drain-pr-stack`

Operational log for draining the accumulated PR stack to `main`.
Generated 2026-06-01.

## §2 Audit — verified chain vs §0 expectation

**Major drift from §0.** The §0 plan assumed an eight-deep chain of *open* PRs to merge
sequentially onto `main`. Reality at audit time:

- **Zero open PRs.** `gh pr list --state open` → empty.
- All seven feature PRs (#31–#37) had **already merged** — but into the integration
  branch `feat/seller-facing-and-platform-growth`, **not** into `main`.
- The eight-deep stack had already collapsed into **one integration branch**, sitting
  **66 commits / 7 PR-merge-commits** ahead of `main` (still at the #30 merge `3234ac92`).
- **No PR existed** (open or closed) from `feat/seller-facing-and-platform-growth` → `main`.

### PRs already merged into the integration branch (history preserved)

| PR | Head → Base | Merge commit | Merged (UTC) |
|----|-------------|--------------|--------------|
| #31 | `chore/seller-slug-in-product-dto` → integration | `2699aa18` | 2026-06-01 05:10 |
| #32 | `feat/platform-growth-share-seo-sitemap` → integration | `73b14dd7` | 2026-06-01 09:54 |
| #33 | `feat/seller-dashboard-ui` → integration | `72347c7f` | 2026-06-01 11:26 |
| #34 | `feat/photo-upload-shared-infra` → integration | `2c71e77a` | 2026-06-01 13:14 |
| #35 | `feat/recommendation-surfaces` → integration | `ad7f7aa6` | 2026-06-01 14:01 |
| #36 | `chore/sellerpayout-schema-split` → integration | `6573b12a` | 2026-06-01 14:29 |
| #37 | `chore/cashback-reference-rate-constant-fix` → integration | `06e19a25` | 2026-06-01 15:00 |

Integration branch tip: `06e19a25`.

### Drift resolution (user-approved)

Per §2/§9 the drift was surfaced and the user chose **"PR + verify + merge"**:
land the integration branch onto `main` via a single PR (#38), preserving all 7
PR-merge commits in `main` history. The §3 sequential per-PR loop is moot — the
per-PR merges already happened on the integration branch.

### CI gap flagged

- `#36` and `#37` are backend-only (Go). Repo workflows (`flutter-ci`, `openapi-ci`,
  `e2e`) are path-filtered to mobile/openapi changes, so **no CI ran** on the `#36`
  (`6573b12a`) or `#37` (`06e19a25`) merge commits on the branch.
- Covered by: local `make verify` on tip `06e19a25` (exit 0) + PR #38's full CI suite.

### Loose end flagged (not actioned — user chose "leave it")

- Untracked `internal/media/integration_test.go` (PR #34 media / migration-0079
  integration test, dated 2026-06-01 14:57) is **never committed anywhere** — lives
  only in the local working tree. Belongs with #34; left for the #34 author to commit
  in a follow-up. Not committed here (no new feature commits during drain).

---

## §3 Merge log

| Step | PR | Action | Result |
|------|----|--------|--------|
| pre-merge verify | tip `06e19a25` | `make verify` (constitution §11) | **exit 0** — race tests, lint 0 issues, boundaries OK, property tests ok, manifest+contrast pass |
| open PR | #38 | `feat/seller-facing-and-platform-growth` → `main` | created, `MERGEABLE / CLEAN` |
| PR CI (1st run) | #38 | full suite | 8/9 pass, 1 required FAIL → see blocker (resolved) |
| blocker fix | `590e0f9b` | `make api-gen` re-sync (user-approved), pushed to branch | 1-line FILES delete; pre-push hook green |
| PR CI (2nd run) | #38 | full suite | **all green** (incl. Generated files in sync) |
| merge | #38 | `gh pr merge --merge --delete-branch=false` | **MERGED** → main `86cfb79e` (2026-06-01 16:02 UTC) |
| post-merge verify | `main` `86cfb79e` | `make verify` | **exit 0** — clean |
| post-merge CI | `main` `86cfb79e` | Flutter CI + OpenAPI Contract | **completed/success** |

### BLOCKER (RESOLVED) — PR #38 first CI run, red required check

`Generated files in sync` (required) failed. Full CI diff was a **single line in one file**:

```
mobile/packages/mopro_api/.openapi-generator/FILES
-test/seller_binding_test.dart
```

- The committed `.openapi-generator/FILES` manifest lists `test/seller_binding_test.dart`;
  a fresh `make api-gen` does not emit that line (OpenAPI generator never lists
  hand-written test files in FILES).
- Generated client **source is in sync** — only the bookkeeping manifest is stale by one line.
- Root cause: commit `fc643808` ("feat(api): /me exposes sellerBinding…", part of **PR #31**)
  added the hand-written `seller_binding_test.dart` and manually added its name to FILES.
- Never caught: the `Generated files in sync` check is path-filtered and didn't run on the
  branch pushes; it runs for the first time on drain PR #38.
- All other 8 checks pass (Go build+contract, flutter test/analyze, OpenAPI lint, build_runner,
  dart analyze, branch-guard).

Per §3.1/§9 the merge was held and surfaced. User chose **"make api-gen on branch"**:
`make api-gen` re-emitted `.openapi-generator/FILES` with the stale line removed (verified the
*only* change was that 1 line, nothing else), committed as `590e0f9b`
(`chore: re-sync openapi FILES manifest …`) and pushed. PR #38 CI re-ran fully green and merged.

---

## §4 Post-drain summary

- **Total PRs landed on main:** 7 feature PRs (#31–#37) via the single drain PR **#38**.
  All 7 PR-merge commits preserved in main history under `86cfb79e`.
- **Main merge commit:** `86cfb79e` (Merge pull request #38). Main moved from `3234ac92` (#30 era).
- **Merge order on main** (oldest first): #31 `2699aa18` → #32 `73b14dd7` → #33 `72347c7f`
  → #34 `2c71e77a` → #35 `ad7f7aa6` → #36 `6573b12a` → #37 `06e19a25` → #38 `86cfb79e`.
- **Post-merge `make verify` on main:** exit 0, clean.
- **Post-merge CI on main:** Flutter CI + OpenAPI Contract both completed/success.
- **Container image rebuild workflow:** **NONE EXISTS.** Repo workflows are `branch-guard`,
  `e2e`, `flutter-ci`, `golden-rebaseline`, `openapi-ci` — none build or push container images.
  The §0/§4.2 assumption (a GitHub Action builds `ghcr.io/mopro/core-svc:latest` on main moves)
  is **not borne out by this repo**. Image rebuild/deploy is an external/manual ops step,
  out of this drain's scope. **Action for ops:** rebuild + roll the core-svc image from
  `main@86cfb79e` so PR #34's photo-upload endpoint becomes reachable (gated on storage
  provisioning per the photo-consumer hold).
- **Branches deleted:** `feat/seller-facing-and-platform-growth` (integration branch, fully
  merged). The 7 feature branches were already auto-deleted when PRs #31–#37 merged into the
  integration branch. Remote now holds only `main`.
- **Deferred items:**
  - Untracked `internal/media/integration_test.go` (PR #34 artifact, never committed) — left in
    local working tree for the #34 author to commit in a follow-up (user chose "leave it").
  - The OpenAPI `FILES` drift fix (`590e0f9b`) rode in on the drain branch rather than a
    standalone PR (user-approved deviation from §6); recorded here for traceability.

---

## §4 Post-drain summary

_To be completed after merge._

- Total PRs landed on main:
- Merge commit on main:
- Container image rebuild workflow:
- Branches deleted:
- Deferred items:
