# Gate finalize — green main, goldens non-blocking, protection enforcing (discovery)

> Turn the safety net from dormant → enforcing with **zero manual steps** and **no
> PAT dependency**: green `main`'s golden check, make golden flips never block a
> merge, require the substantive checks in branch protection, and clean the stale
> worktrees.

## State found

- **`main` is red.** #163 (PD-07) merged (admin) with `flutter test` failing on 4
  legitimately-flipped `pdp_reviews_tab_populated` goldens → `Flutter CI` on `main`
  is failing.
- **Branch protection is effectively OFF** — `required_status_checks.contexts =
  ['verify']` only. None of the substantive Flutter/contract/vuln checks are
  required (which is *how* #163 merged red).
- **`flutter test` is one job** (`flutter-ci.yml` `test`, `name: flutter test`)
  running ALL tests incl. **23 `*_goldens_test.dart` files**. Goldens are **not
  tagged**; there is **no `mobile/dart_test.yaml`**.
- **`golden-rebaseline.yml` checks out with `secrets.GOLDEN_REBASELINE_PAT`** (from
  #155) — unset, so it can't run.

## Plan

### A. Split goldens → informational (kills the PAT requirement) — CI PR
- Tag each `*_goldens_test.dart` with a file-level `@Tags(['golden'])` (+
  `mobile/dart_test.yaml` declaring the tag).
- `flutter-ci.yml`: the existing **`flutter test`** job runs
  `flutter test --exclude-tags golden` (the **logic** gate — required). Add a new
  **`flutter golden (informational)`** job running `flutter test --tags golden`
  (never required → golden flips can't block a merge).
- `golden-rebaseline.yml`: revert checkout to the default `GITHUB_TOKEN` (drop the
  PAT line). With goldens non-blocking, the recursion-guard reason is moot —
  `GITHUB_TOKEN` pushes (to a branch or directly to `main`) land fine; **no PAT is
  required for anything**. (A PAT stays a *nice-to-have* if you ever want the bot's
  PR-branch commits to re-trigger checks, but nothing depends on it.)

### B. Green `main`'s goldens (no PAT) — direct op
- After A merges: `gh workflow run golden-rebaseline.yml --ref main` → it
  `flutter test --update-goldens` on Linux and commits the rebaselined goldens
  **directly to `main`** with `GITHUB_TOKEN` (a direct-main push needs no
  recursion workaround). Watch → `Flutter CI` green on `main`.

### C. Apply branch protection (enforce) — `gh api` direct op
- `PATCH .../branches/main/protection/required_status_checks` with the
  **substantive** contexts (exact names from `gh pr checks`): `verify`,
  `flutter analyze`, `flutter test` (now logic-only), `build_runner (verify
  generated files up-to-date)`, `i18n completeness (extras gate)`, `i18n dead-key
  gate`, `riverpod inference gate`, `dart analyze (mopro_api generated client)`,
  `govulncheck ./...`, `Go build + contract tests`. **Exclude** `flutter golden
  (informational)`.
- Sanity: a deliberately-broken compile must fail the required `flutter test`/`flutter analyze`.

### D. Worktree cleanup — direct op
Remove the 6 merged-PR worktrees (lane-b #155, pd07 #163, pdp-readpath #158,
pdp-seed #157, plp13 #159, plp13b #161). **Keep** `mopro-lane-c`
(`feat/search-suggestions-se06`, no merged PR) + the main clone (active PLP-13 PR4).

## Notes / shifts

- The CI workflow change ships as a PR; B/C/D are direct `gh`/`git` ops.
- Golden split is **tag-based** (idiomatic, `--exclude-tags`/`--tags`), not
  path-based (flutter test can't exclude by path).
