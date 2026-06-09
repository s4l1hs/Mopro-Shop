# F-022 — Main Dependency Stability (riverpod pin + Dependabot hardening)

> Discovery for `fix/riverpod-pin-dependabot-hardening`. Dependabot landed a breaking
> major (`flutter_riverpod` 2.6.1 → 3.3.1, PR #120) without migrating the code, briefly
> leaving the mobile app non-compiling. This doc records the actual state, the root cause,
> and the exact branch-protection fix. **Local-verify; deploys deferred.**

## 1. State of `main` now (verified)

- `main:mobile/pubspec.yaml` → `flutter_riverpod: ^2.6.1`. **The IA-02 pin carried back.**
  The revert commit is `7aa9f4d4 chore(mobile): pin flutter_riverpod to ^2.6.1 (revert
  breaking 3.x bump)`, which rode in on the `feat/coin-hub` merge (#124) to `main`.
- `mobile/pubspec.lock` resolves `flutter_riverpod: 2.6.1` (transitive `riverpod` 2.x).
- `flutter analyze` on this branch: **0 errors, 0 warnings, 199 infos**. The infos are the
  pre-existing `very_good_analysis 10.2.0` lint tightening (DEFER'd tech-debt, F-022 §3.3),
  not compilation failures. **main compiles.**

→ So §3.1 is a **confirmation, not a change** (escape hatch §1.3). The pubspec needs no edit;
  both `main` and this branch are already pinned to `^2.6.1`.

## 2. Dependabot PR #120

- **MERGED** 2026-06-08 10:39 UTC (`b209656c` bump → merge `d9805e6d`). It bumped riverpod
  to **3.3.1** — a breaking major (`StateProvider` removed, `AsyncValue` API changed) — with
  no code migration, which is what produced the transient 785-error non-compiling tree.
- The pin-revert (`7aa9f4d4`) landed **after** the merge, on the coin-hub branch, restoring 2.x.
- **No other open Dependabot PRs** (`gh pr list --author app/dependabot --state open` → empty).
  In particular the very_good_analysis 10.2.0 bump is not currently open as a PR; its analyze
  infos are a separate tech-debt item (DEFER'd).

## 3. `.github/dependabot.yml` (before)

Three ecosystems: `gomod` (/), `github-actions` (/), `pub` (/mobile). Each weekly (Mon),
limit 5, minor+patch **grouped**; majors come solo. **No `ignore` rules. No auto-merge config.**
So a breaking major (riverpod 3.x) was auto-proposed solo and — with no blocking CI — merged.

## 4. Root cause: Flutter CI is not a required status check

Branch protection on `main` (`gh api repos/:owner/:repo/branches/main/protection/required_status_checks`):

```
strict: false
contexts: ["verify"]        # make-verify.yml only
```

`flutter-ci.yml` defines jobs **`flutter analyze`**, `build_runner (verify generated files
up-to-date)`, and `flutter test` — but **none are required**. PR #120 went red on
`flutter analyze` yet still merged because only `verify` blocks, and `verify` does not run
`flutter analyze`. **This is the systemic gap**: a non-compiling mobile PR was mergeable.

### Exact fix (Salih repo-settings action — not code)

GitHub → repo **Settings → Branches → Branch protection rule for `main`** →
**"Require status checks to pass before merging"** → add the check named **`flutter analyze`**
(the job `name:` in `flutter-ci.yml`). Optionally also add **`flutter test`** and
**`build_runner (verify generated files up-to-date)`**.

API equivalent (adds `flutter analyze` alongside the existing `verify`):

```bash
gh api -X PATCH repos/:owner/:repo/branches/main/protection/required_status_checks \
  -f strict=false \
  -f 'contexts[]=verify' -f 'contexts[]=flutter analyze'
```

Once required, a PR that fails `flutter analyze` (as #120 did) **cannot merge** — closing
the root cause that let a breaking major land on `main`.

## 5. Actions taken on this branch

- §3.1 — confirmation only (pin already `^2.6.1`, main green).
- §3.2 — `dependabot.yml`: ignore `version-update:semver-major` for the `pub` (Flutter) app so
  a breaking major can no longer be auto-proposed/merged until a deliberate migration. No
  auto-merge existed to disable.
- §3.3 — REPORT.md entry; DEFER (a) the real riverpod 2.x→3.x migration and (b) the
  very_good_analysis 10.2.0 analyze-infos. #120 stays merged-then-reverted; the new ignore
  rule prevents 3.3.1 re-landing.
