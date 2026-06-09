# CI / workflow cleanup — discovery (Lane B)

> Three CI cleanups on `chore/ci-cleanup`: de-dup the vuln scanner, make the
> golden-rebaseline bot's commits fire CI, and regenerate the stale PLP-14
> price-drop-toggle goldens. Owns `.github/workflows/**` + the `*_sidebar_*`
> toggle goldens only.

## 1. Scanner de-dupe — the two workflows are equivalent

- `govulncheck.yml` — `pull_request` (paths: `**.go`, `go.mod`, `go.sum`, the
  workflow file) + weekly `schedule` (Mon 06:17 UTC) + `workflow_dispatch`.
- `security-scan.yml` — `push: [main]` + `pull_request: [main]` +
  `workflow_dispatch`.
- **Same scan, same job name** (`govulncheck ./...`), same `set -o pipefail;
  govulncheck ./... | tee "$GITHUB_STEP_SUMMARY"`, same fail-on-vuln (govulncheck
  exits 3 on a reachable vuln → job fails; no `continue-on-error`). The only
  things `security-scan.yml` adds: the **push-to-main** trigger, `cache: true`,
  `timeout-minutes: 10`.
- **Plan:** add `push: branches: [main]` to `govulncheck.yml` (keeping its
  path-filtered PR + weekly + dispatch + exit-3 behavior), then **delete
  `security-scan.yml`**. The required check context `govulncheck ./...` is
  unchanged (it stays the job name in `govulncheck.yml`). Fold in
  `timeout-minutes: 10` as a cheap safety net.

## 2. Rebaseline bot — commits don't fire CI

- `golden-rebaseline.yml` checks out with the implicit `GITHUB_TOKEN`, then
  `git commit` + `git push` the re-baselined goldens. **Pushes authenticated with
  `GITHUB_TOKEN` do not trigger workflows** (GitHub's recursion guard) — so a
  golden PR that ends on a rebaseline commit never re-runs the required checks
  and hangs "waiting for status" (the close/reopen dance, CUTOVER_LEDGER §5).
- **Fix:** pass a PAT to `actions/checkout` (`token: ${{ secrets.GOLDEN_REBASELINE_PAT }}`);
  checkout persists that credential, so the later `git push` runs as the PAT and
  **does** fire CI. No change to the commit/push step itself.
- **Secret does not exist yet** (`gh secret list` → only `DEPLOY_*`). The
  workflow is wired to read `GOLDEN_REBASELINE_PAT`; Salih adds it once with a
  fine-grained PAT (repo `contents: write`):

  ```
  gh secret set GOLDEN_REBASELINE_PAT --repo s4l1hs/Mopro-Shop --body '<fine-grained-PAT>'
  ```

## 3. Stale goldens — PLP-14 toggle

- PR #153 (PLP-14) added a price-drop `SwitchListTile` row to `FilterPanel`, which
  renders in the desktop PLP **and** search sidebars, and **did not** regenerate
  goldens locally (anti-goal — Linux-only). After #153 merged to `main`, the
  `plp_sidebar_*` + `search_sidebar_*` baselines are stale → the `flutter test`
  gate would fail on them.
- **Plan:** dispatch `golden-rebaseline.yml` on `chore/ci-cleanup` (based on
  `origin/main`, which includes the merged toggle) to regenerate on Linux. The
  bot commits + pushes the new baselines back to the branch.
- **Ordering (matters):** the PAT secret does not exist yet, so the regen run must
  use the **current `GITHUB_TOKEN`** workflow. Dispatch the rebaseline **before**
  committing the PAT switch; the GITHUB_TOKEN push works on the unprotected
  feature branch. Reconcile: only `*_sidebar_*` PNGs should flip (the new toggle
  row); anything else flipping is a discovery shift to investigate.
