# F-022b — Flutter CI analyze: green-on-compile + required check

> Completes [F-022](./f022-deps-stability.md). F-022 hardened Dependabot and
> identified the root cause (Flutter CI not required) but left the `flutter
> analyze` job **red** on 199 infos — so it could not be made required. F-022b
> makes analyze green-when-compiling, then it can be required.

## Where analyze runs

- **Workflow:** `.github/workflows/flutter-ci.yml`, job `analyze`
  (`name: flutter analyze`), step `:32` → `- run: flutter analyze`.
- **Exact PR check-context name:** **`flutter analyze`** (confirmed via
  `gh pr checks 137`). Branch protection must match this string verbatim.
- Invocation is a plain `flutter analyze` (no melos / wrapper) — the §3.1 change
  is the single step on line 32.

## main's analyze breakdown (the gate math)

```
flutter analyze            → 0 errors, 0 warnings, 199 infos → exit 1 (infos fatal)
flutter analyze --no-fatal-infos → exit 0   (errors + warnings still fatal)
```

- **0 errors / 0 warnings / 199 infos** — so `--no-fatal-infos` alone greens it;
  no warnings to fix first (escape hatch §1.3 / split §5 not triggered).
- The 199 infos are pre-existing `very_good_analysis 10.2.0` debt — **DEFER'd**,
  not touched here (anti-goal #2).

## Current default-branch protection

- `repos/s4l1hs/Mopro-Shop/branches/main/protection/required_status_checks`:
  `{ "strict": false, "contexts": ["verify"] }` — **only `verify`** is required
  (the make-verify.yml job, which does NOT run `flutter analyze`). This is the
  exact hole that let the riverpod 3.x bump (785 errors) merge.

## Other jobs — require-readiness (all green on #137)

| Context name (verbatim) | Status | Require-ready |
|---|---|---|
| `flutter analyze` | red→**green after §3.1** | ✅ (the point of this PR) |
| `flutter test` | green | ✅ |
| `build_runner (verify generated files up-to-date)` | green | ✅ |
| `i18n completeness (extras gate)` | green | ✅ |
| `i18n dead-key gate` | green | ✅ |
| `riverpod inference gate` | green | ✅ |
| `dart analyze (mopro_api generated client)` | green | ✅ |
| `verify` | green (already required) | ✅ |

## Plan

- §3.1: `flutter-ci.yml:32` → `flutter analyze --no-fatal-infos`.
- §3.2: document the exact branch-protection PATCH (full contexts incl. `verify`)
  for Salih to apply **after merge**, once analyze is green on main.
