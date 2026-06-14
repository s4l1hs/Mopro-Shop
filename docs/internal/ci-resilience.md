# CI resilience — transient-flake hardening

> A transient `curl` connect failure to `imagemagick.org` reddened the **required**
> `verify` gate on PR #226 (docs-only). That's one instance of a class: **CI steps
> that touch the network (installs, downloads, pulls) transiently fail and redden a
> required gate.** This doc inventories every network-dependent step and records
> the fix, so the class is closed, not just the instance. Branch
> `chore/ci-resilience`.

## Bright line (non-negotiable)

Retries/caching are **only** for genuinely-transient *infra/transport* ops —
install, download, pull. **Never** wrap a build/test/lint/gen-sync step (anything
that asserts correctness) in a retry or `continue-on-error`. A red from a real
failure is **fixed, never retried into green** — that is the override sin in
disguise, and we just closed the override hole (`enforce_admins=true`,
`docs/internal/main-drift-forensics.md`). `continue-on-error` stays only on the
already-informational `flutter golden` job.

## Fix preference: eliminate > cache > retry

## Inventory + disposition

| Step | Workflow(s) | Required gate? | Class | Disposition |
|---|---|---|---|---|
| `curl` ImageMagick 7 AppImage (imagemagick.org) | make-verify | **yes** (`verify`) | binary fetch | **retry+timeout** — `--retry 5 --retry-delay 5 --retry-all-errors --retry-connrefused --connect-timeout 30 --max-time 300`. *(This is the #226 flake. Eliminate-via-container considered — see below — but containerizing the verify job, which needs Go+Flutter+Docker-in-Docker, is disproportionate; retry closes the flake.)* |
| `curl` golangci-lint `install.sh` (raw.githubusercontent.com) | make-verify | **yes** (`verify`) | binary fetch | **retry+timeout** — same flags; also fetch-to-file then run (no `curl \| sh`, which a mid-stream blip would partially-pipe). |
| `actions/setup-go@v6` `cache: true` (go mod download) | make-verify, govulncheck, openapi-ci ×2 | yes | toolchain dep | **already cached.** Added missing `cache: true` to **nightly** (was uncached). Cache hit = no module fetch. |
| `subosito/flutter-action@v2` (Flutter SDK download) | make-verify, flutter-ci, openapi-ci, golden-rebaseline, nightly… (×10) | yes | toolchain dep | **SHA-pinned** (`1a44944…` # v2) — supply-chain + stability. SDK download is GitHub-hosted (robust); built-in `cache: true` is an available further step if it ever flakes (noted, not applied — no observed flake). |
| `flutter pub get` / `dart pub get` / `build_runner` | flutter-ci, openapi-ci, make-verify, golden-rebaseline | yes | dep fetch | pub.dev is highly available; runs after the (cached) SDK. No retry added (no observed flake); `build_runner` itself is **not** network (it asserts gen-sync — must stay un-retried per the bright line). |
| `docker/login-action`, `docker/setup-buildx-action`, `docker/build-push-action` | build-images | no (build-images isn't a required PR gate) | registry/login | **SHA-pinned** (docker org tags → SHAs). `build-push-action` handles its own transport; login is robust. |
| host GHCR `docker pull` | deploy (on host, not runner) | n/a (workflow_dispatch) | registry pull | PAT-based on the VDS; not a PR-gate runner step. Out of this sweep. |
| third-party `uses:` (subosito, docker/*) | various | — | supply chain | **all SHA-pinned** with a `# vN` comment; first-party `actions/*` (checkout, setup-go) left on major tags (lower supply-chain risk, standard practice). |
| per-job `timeout-minutes` | flutter-ci, openapi-ci, branch-guard, build-images, golden-rebaseline | mixed | hang guard | **added `timeout-minutes: 30`** to jobs that had none (GitHub default is 6h → a hang would burn the runner then fail). make-verify/govulncheck/nightly/deploy already had job timeouts. |

## What got eliminated vs cached vs retried

- **Retried (transport only):** both raw `curl` installs in `make-verify` (ImageMagick + golangci-lint) — the actual flake class, on the required gate.
- **Cached:** Go modules via `setup-go cache:true` (added the missing one in nightly; others already on).
- **Eliminated:** none structurally this pass — see "Deferred" (containerizing verify is the durable eliminate for the ImageMagick fetch but is a large, riskier change).
- **Pinned:** all third-party actions → SHA.
- **Bounded:** per-job `timeout-minutes` on the jobs that lacked them.

## Deferred / noted (not done this pass)

- **Containerize the `verify` job** in a prebuilt image with Go+Flutter+ImageMagick baked in → removes the per-run installs entirely (the true *eliminate*). Disproportionate now (verify also needs Docker-in-Docker for property/e2e DB containers); retry closes the observed flake. Tracked here if install flakes recur.
- **`subosito/flutter-action` `cache: true`** across the 10 uses — caches the SDK download; apply if SDK fetch ever flakes.
- **Pre-existing actionlint finding (not introduced here):** `branch-guard.yml:19` uses `github.head_ref` directly in an inline script ([expression] script-injection note). A real (minor) hardening opportunity — pass it via env — but pre-existing and out of this PR's scope.

## Verification

`actionlint` clean (0 errors; the lone `branch-guard` `[expression]` note is pre-existing). All 9 workflows YAML-parse. No required gate weakened or made informational; no assertion step retried.

## The rule (also in CONTRIBUTING)

Any **new** workflow step that installs / downloads / pulls **must** be
containerized/cached or retry-wrapped **and** time-bounded. Retries apply to
infra/transport only — **never** to assertions. A red required check means *fix
something real*; it is never retried or overridden.
