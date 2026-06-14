# Merge-queue automation — decision + fallback

> Goal: kill the manual "Update branch" rebase that `strict=true` (required branches
> up to date) forces whenever PRs queue up — **without** losing its anti-drift safety
> (nothing merges stale). Branch `chore/merge-queue`. No deploy.

## §1 — Availability: empirically determined → **UNAVAILABLE** (fallback path)

Probed the rulesets API (raw JSON in `merge-queue-probe-result.json`):

- `POST /repos/s4l1hs/Mopro-Shop/rulesets` with a `{type: "merge_queue"}` rule →
  **HTTP 422** `Invalid rule 'merge_queue'` in **all** enforcement modes
  (`disabled`, `evaluate`, `active`).
- Control: the same endpoint **accepts** a `{type: "required_linear_history"}` rule
  (created + deleted cleanly) → the rulesets API works; the **`merge_queue` rule type
  itself is rejected**.
- Repo is **public** but owned by a **personal User account** (`s4l1hs`).

**Conclusion:** GitHub merge queue is an **Organization / Enterprise** feature; it is
not available on personal-account repositories regardless of public visibility. We do
**not** force it (§1 guidance). → **§4 fallback.**

(If Mopro ever moves to an org, the primary path is a one-liner: create a repo ruleset
with a `merge_queue` rule on `~DEFAULT_BRANCH`, wire `merge_group:` into the 5
required workflows — make-verify, flutter-ci, openapi-ci, govulncheck, branch-guard —
and drop `strict` so the queue becomes the up-to-date mechanism. The 14 required
contexts + `enforce_admins=true` stay. That migration is pre-mapped here.)

## §4 — Fallback shipped: auto-update-branch + auto-merge

Two pieces, together a serialized always-current hands-off flow that **keeps `strict`
exactly as-is** (so the anti-drift guarantee is untouched):

1. **Repo settings enabled** (live; `before/after-repo-settings.json`):
   - `allow_auto_merge = true` — authors can click **"Enable auto-merge"**; the PR
     merges itself once all 14 required checks pass **and** it's up to date. Auto-merge
     respects every required check, `strict`, and `enforce_admins` — it bypasses nothing.
   - `allow_update_branch = true` — enables the update-branch path.
2. **`.github/workflows/auto-update-pr-branch.yml`** — on every push to `main`, finds
   open PRs that **opted in via auto-merge** and are now **BEHIND** main, and updates
   their branch (merges main in). That re-runs the required checks against current main;
   when they pass + up to date, that PR's auto-merge merges it → pushes main → cascades
   to the next behind PR. One-at-a-time, always current, no manual "Update branch".

### One-time setup the owner must do (for the re-test to fire)
A branch update authored by the default `GITHUB_TOKEN` does **not** re-run workflows
(Actions recursion guard) — so required checks wouldn't refresh on the updated head.
Set a PAT secret so the update is authored by a real identity:

```
gh secret set AUTO_MERGE_PAT -R s4l1hs/Mopro-Shop   # paste a PAT with `repo` scope
```

The workflow uses `secrets.AUTO_MERGE_PAT` if present, else falls back to
`GITHUB_TOKEN` (branch still updates; you may need to nudge checks once).

## Invariants preserved (anti-goals)
- `strict=true` **kept** — the queue's job (up-to-date-before-merge) is done by
  auto-update + auto-merge; nothing can merge untested-against-current-main.
- 14 required contexts **unchanged**; `enforce_admins=true` **unchanged**.
- No override-merge; no deploy. Branch protection JSON is byte-identical before/after
  (only repo *settings* `allow_auto_merge`/`allow_update_branch` flipped).

## Verify (full hands-off cycle)
The workflow fires on push to main, so it only takes effect **once this PR is merged**
(workflows resolve from the default branch). After merge + `AUTO_MERGE_PAT` set:
1. Open two trivial PRs; click **Enable auto-merge** on both.
2. Let the first merge. On that push to main the second goes BEHIND → the workflow
   updates it → checks re-run → it auto-merges. **No manual "Update branch" on either.**
