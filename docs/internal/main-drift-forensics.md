# Main-drift forensics — how red `gofmt`/`build_runner` landed on `main`

> After the banked-engineering wave (#217/#218/#221/#222/#223), `main` was found
> carrying red `gofmt` (`verify`) and `build_runner`/gen-sync drift (stale
> `product.g.dart`, `size_recommendation.g.dart`, then `return_request*.g.dart`).
> This is the diagnose-first forensics: **how** the red got on main, and the
> hardening that closes that exact mechanism. Branch `chore/main-drift-forensics`.

## Verdict

**Mechanism = OVERRIDE (admin bypass via `enforce_admins=false`).** Every suspect
PR had a **required** status check **red at the exact head SHA that merged**, and
merged anyway. This is not stale-branch (the checks were red *at head*, not
green-but-behind) and not a gate gap (the failing checks **are** in the required
list). `strict=false` is a real *secondary* weakness (latent stale-branch class)
but was **not** the proximate cause here.

## §1 — Current main state (at investigation time, HEAD `126bbfdd` = #223)

| Check | Result on a clean `origin/main` |
|---|---|
| `gofmt -l .` | ✅ clean (fixed by #222 commit `5acd9dec`) |
| `go build ./...` | ✅ clean |
| `build_runner` (fresh regen + `git status`) | ❌ **STILL DRIFTED** — `return_request.g.dart` + `return_request_items_inner.g.dart` regenerate (RT-05 `reason`/`note`, RT-03 `photo_keys` missing from committed gen). 23 insertions, additive. |
| `verify` (full, DB integration) | ❌ **RED** — `returns_integration_test` 42703 `column "reason" of relation "return_items" does not exist` (the hand-rolled test schema lacked the RT-05 columns migration 0103 adds in prod). |
| `flutter test` | ❌ **RED** — (a) `return_flow_provider` `buildRequest` stopped folding per-item notes into the header `description` (the RT-05 commit dropped the line); (b) `flow_w` asserted the removed `returns.tracking_no` (RT-02 replaced it with the cargo drop-off code). |

→ **All fixed forward in this PR.** Crucially, the breakage was **broader than
codegen**: #223 merged with `verify` **and** `flutter test` red too (consistent
with the §2 evidence — #223's head had all three red). The gen-drift class also
**recurred one PR after #222 fixed the previous instance** — #223 re-introduced it
14s later. This is the full blast radius of one overridden merge: a stale generated
file, a stale test schema, a dropped feature line, and a stale test assertion — none
of which a green-required-checks merge would have allowed.

## §2 — Branch-protection config (`main`, captured to PR as `protection_before.json`)

| Setting | Value | Implication |
|---|---|---|
| `required_status_checks.strict` | **false** | branches need not be up-to-date before merge → latent stale-branch drift class |
| `required_status_checks.contexts` | **14**, incl. `verify`, **`build_runner (verify generated files up-to-date)`**, `Generated files in sync`, `flutter test` | the failing checks **ARE required** → **GATE-GAP ruled out** |
| `enforce_admins` | **false** | the escape hatch — an admin can merge over red required checks |
| `required_pull_request_reviews` | **none** | no second pair of eyes; a single admin can self-merge anything |
| `required_linear_history` / `allow_force_pushes` | false / false | — |

## §2 — Per-PR merge evidence (required-check conclusions at the merged head SHA)

`gh api .../commits/<headSHA>/check-runs` at each PR's `headRefOid` (the commit
that actually merged):

| PR | merged | head SHA | `verify` | `build_runner` | `flutter test` | classification |
|---|---|---|---|---|---|---|
| #217 (size charts BE) | 09:33Z | `8c8441de` | ✅ | ❌ **failure** | ✅ | **OVERRIDE** |
| #218 (size charts UI) | 10:10Z | `c319ef20` | ✅ | ❌ **failure** | ✅ | **OVERRIDE** |
| #221 (pdp-batch) | 11:24Z | `f3d4b4cb` | ❌ **failure** | ❌ **failure** | ✅ | **OVERRIDE** (introduced gofmt drift via PD-04 `SellerRatingAvg`, commit `10410ae0`; + stale `product.g.dart`) |
| #222 (membership) | 12:58:16Z | `ac524899` | ✅ | ✅ | ✅ | **clean** (only `flutter golden (informational)`, non-required; incidentally fixed #221's gofmt+gen drift) |
| #223 (returns) | 12:58:30Z | `d441bc11` | ❌ **failure** | ❌ **failure** | ❌ **failure** | **OVERRIDE** (re-introduced gen drift 14s after #222 fixed it; merged with **three** required checks red) |

**Reading:** four of five PRs merged with ≥1 **required** check red at the merged
SHA. #223 merged with `verify` **and** `build_runner` **and** `flutter test` red.
The only clean merge was #222. `strict=false` is consistent with the
near-simultaneous #222/#223 merges (#223 never rebased onto #222), but the decisive
fact is the **red-at-head** required checks — that is override, regardless of strict.

## §3 — Hardening (matched to OVERRIDE)

`strict=true` would **not** have stopped these merges (it forces up-to-date
branches; it does not stop an admin overriding a red check). Adding contexts is
moot (already required). The fix that closes OVERRIDE is **removing the bypass** —
a config change with a real tradeoff, so it is **flagged for Salih, not flipped
unilaterally** (lane §3/§5):

- **`enforce_admins=true`** (DECISION FOR SALIH). Closes the hole completely:
  nobody — admins included — can merge over a red required check. **Tradeoff:** it
  removes the deliberate escape hatch used for genuinely-stuck/flaky required
  checks. If kept `false`, the discipline below is the only guard.
- **Discipline (documented now, CONTRIBUTING "Merging & branch protection"):** admin
  override is for **confirmed infra flakes only** — never a red `verify`/`gofmt`,
  `build_runner`/gen-sync, or `flutter test`. Those are deterministic; red means
  the branch is wrong, not the runner.
- **Defense-in-depth (optional, also for Salih):** `strict=true` *or* a GitHub merge
  queue closes the latent stale-branch class (each lane green alone, combined main
  drifts). Tradeoff: every PR must rebase onto latest main before merge → merges
  serialize. Not applied here (doesn't address the proximate OVERRIDE cause; the
  parallel-lane workflow prefers non-serial merges).

**No branch-protection API change was made by this PR.** `protection_before.json`
== current state; any flip awaits Salih's decision.

## §4 — Mandatory post-batch main-green check (the backstop)

Documented in CONTRIBUTING. After **any wave of parallel-lane merges**, on a clean
`origin/main`:

```bash
make verify
( cd mobile/packages/mopro_api && dart run build_runner build --delete-conflicting-outputs ) && git status --short   # must be empty
gofmt -l .   # must be empty
```

Red here = a cross-lane interaction (combined-test or combined-codegen drift); **fix
forward immediately**, do not leave main red. Precedents: **#208** (combined *test*
breakage from #203×#204×#205) and **this** (combined *codegen* + gofmt from
#217/#218/#221/#223). This check would have caught every instance on day one.

## Why this recurred despite documentation

CONTRIBUTING already documented the two-stage codegen gate ("Generated DTOs are
source-of-truth", incl. the `build_runner` `.g.dart` stage) **before** these merges.
The gate existed, was required, and was red — and PRs merged anyway. So the failure
was **not** a knowledge or tooling gap; it was a **merge-discipline gap** (override
of a red required check). Hence the hardening is discipline + the `enforce_admins`
decision, not a new check.
