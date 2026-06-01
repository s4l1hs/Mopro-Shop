# CI Infrastructure + Cleanup Baseline — `chore/ci-infrastructure-and-cleanup`

Generated 2026-06-01. Base: `main@9efd35bc` (PR #40 e2e revival merged; PR #38 stack drain in history).

## §4.1 Existing workflows

| File | Name | Triggers | Runs |
|------|------|----------|------|
| `branch-guard.yml` | (PR hygiene) | `pull_request: ["**"]` | `refuse-pr-from-default-branch` |
| `e2e.yml` | E2E Tests (**Playwright**) | push/PR `main` (paths) | `pnpm test:e2e` — **frontend** e2e, NOT `internal/e2e/` |
| `flutter-ci.yml` | Flutter CI | push/PR (mobile/openapi paths) | flutter analyze/test, dart client gen checks |
| `golden-rebaseline.yml` | golden rebaseline | manual/dispatch | golden image rebaseline |
| `openapi-ci.yml` | OpenAPI Contract | push/PR `main` (paths) | Spectral lint + **Go build + contract tests** |

**Confirmed: none build container images; none run `make verify`.** (Matches PR #38/#40 findings.) Backend-only Go changes are partially covered by openapi-ci's "Go build + contract tests" but that does **not** run `-tags=integration` (so the e2e suite stays invisible there too).

## §4.2 Container build artifacts

- **No per-service Dockerfiles** (`cmd/core-svc/Dockerfile` etc. do **not** exist).
- **One multi-service Dockerfile**: `build/Dockerfile` — parameterized `ARG SERVICE=core-svc|fin-svc|jobs-svc`, builds `./cmd/${SERVICE}` to a distroless static image; injects `BUILD_SHA`/`BUILT_AT` ldflags into `internal/buildinfo`.
- **Existing local build tooling**: `make docker-build` already builds all three via `build/Dockerfile` + `--build-arg SERVICE=` → `mopro/<svc>:$(VERSION)`. The CI workflow mirrors this.
- **`deploy/docker-compose.yml`** references `ghcr.io/mopro/{core,fin,jobs}-svc:${VERSION:-latest}` — so production expects the `ghcr.io/mopro/` namespace.

⇒ §5 workflow must use `file: build/Dockerfile` + `build-args: SERVICE=<svc>`, **not** the prompt's `cmd/${service}/Dockerfile`. Matrix = `[core-svc, fin-svc, jobs-svc]` (all three build from the one Dockerfile).

## §4.3 Registry authentication — BLOCKER for §5.2 smoke test

- Production namespace is **`ghcr.io/mopro/`** (org `mopro`).
- This repo is **`s4l1hs/Mopro-Shop`**. A workflow here authenticates with `GITHUB_TOKEN` scoped to the **`s4l1hs`** owner — it can push to `ghcr.io/s4l1hs/...` but **NOT** `ghcr.io/mopro/...` (a different org it doesn't own).
- ⇒ The §5.2 `workflow_dispatch` image-push smoke test **cannot succeed from this fork** without `mopro`-org GHCR access (org membership + a PAT/org token with `packages:write`, or the repo living under the `mopro` org). **This is §1.6 trigger #1** (pre-authorized split): ship the workflow definition correct-for-production; carry the registry-credential validation + first real push to a follow-up that runs where `mopro`-org creds exist.

## §4.4 `make verify` characteristics (post-PR-#40)

`verify: fmt vet test lint boundaries property-cashback property-payout property-ledger property-timex property-order integration-e2e verify-image-manifest verify-contrast`

- **Docker-bootstrapped** sub-targets: `property-*` → `pg-ledger-test-up` (pg-ledger-test:6434, applies real init+migrations); `integration-e2e` → `e2e-test-up` (redis-e2e:6381, pg-ecom-e2e:6435, pg-ledger-e2e:6436 + real ledger schema). Both idempotent via `docker run`.
- **Needs Flutter**: `verify-contrast` → `cd mobile && flutter test test/design/contrast_test.dart`; `verify-image-manifest` writes the asset manifest.
- **Needs Go 1.25** (per `build/Dockerfile` golang:1.25-alpine; confirm `go.mod`).
- ⇒ §6 make-verify CI must install **Go + Flutter** and have **Docker** available (ubuntu-latest has Docker). The prompt's §6 template (Go + compose only) is insufficient — Flutter setup required, and the make-verify path uses `docker run` (not a static compose service list), so the template's `services:`/`docker compose up` block doesn't match; let the Makefile's own bootstrap create the containers.
- Local runtime: ~3–4 min (most go-test cached) to ~10+ min cold. CI cold runtime TBD (watch §1.6 trigger #2 ≤15 min).

## §4.5 Orphan file decision — DELETE

`internal/media/integration_test.go` (172 lines, `package media_test`, 3 `Test*` functions):

- **Does not compile**: references `media.PhotoAttachment`, `media.NewService/NewRepository`, `media.AttachInTx`, `media.ListByEntity`, `media.EntityReview`, `media.ErrNotOwned`, `media.ErrLimitExceeded` — **none exist** in the current `internal/media` package (`go vet` → `undefined: media.PhotoAttachment`). That surface moved to `internal/attachments` in PR #34.
- **Wrong schema**: queries `media_schema.photo_attachments`; migration 0079 creates `attachments_schema.photo_attachments`.
- **100% superseded**: `internal/attachments/integration_test.go` (PR #34, committed + gated by `make verify`) has the **identical three scenarios** (`TestIntegration_MigrationRoundTrip`, `_UploadAndAttach`, `_AttachOwnershipReattachLimit`) against the correct package + schema.

⇒ **Decision: `git rm`.** Zero unique coverage; non-compiling draft against an abandoned surface. §1.6 trigger #3 (preserve substantial unique scenarios) does **not** apply — the scenarios are already preserved in `internal/attachments`.

## §1.6 triggers fired

- **#1 (registry/infra)**: YES — `ghcr.io/mopro/` not pushable from the `s4l1hs` fork → image-build workflow ships as definition (5a); real push + credential validation deferred to follow-up. Also adapted: `build/Dockerfile`+SERVICE (no per-service Dockerfiles); make-verify CI needs Flutter+Docker.
- **#3 (orphan)**: NO — orphan is duplicated/dead → delete, not preserve.
- **#2 (runtime >15min)**: TBD from the make-verify CI smoke run.

## Out-of-filesystem note (§3 runbook)

The storage provisioning runbook is **not in this repo or any `outputs/` dir** — it lives in the user's external scratchpad. Claude cannot edit a file it can't access; the three §3 corrections are provided as text for the user to apply.
