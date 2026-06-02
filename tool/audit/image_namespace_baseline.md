# Image-Namespace Parameterization — Baseline

Branch `chore/parameterize-image-namespace`. Base `main@e0c2688e` (PR #50 merged).

## The mismatch (confirmed)
- **CI push target** (`build-images.yml:43-48`): `ns=ghcr.io/${owner,,}` where
  `owner = github.repository_owner` → resolves to **`ghcr.io/s4l1hs/<svc>`** on this
  fork. Tags: `:latest`, `:<sha>`, `:<short_sha>` (with `VERSION` default `latest`).
- **Compose puller** (`deploy/docker-compose.yml`): pins **`ghcr.io/mopro/<svc>`** —
  an org namespace that doesn't exist under the current owner → `docker compose pull`
  404s. This PR parameterizes the puller; the pusher is untouched (non-goal).

> GHCR package-version listing could not be done from here (`gh` token lacks
> `read:packages` → 403); the green `build (<svc>)` check-runs on `7b8d96cc`
> (PR #50 audit) are the evidence the `s4l1hs` tags exist.

## §2.1 — Every `ghcr.io/` / `mopro/` image reference + classification

| File:line | Context | Classification |
|---|---|---|
| `deploy/docker-compose.yml:382,421,454` | `image: ghcr.io/mopro/{core,fin,jobs}-svc:${VERSION:-latest}` — the puller | **PARAMETERIZE** → `ghcr.io/${IMAGE_NS:-mopro}/…` |
| `deploy/docker-compose.prod.yml:364,398,427` | `image: mopro/{core,fin,jobs}-svc:${VERSION:-latest}` — **Docker Hub** registry (no `ghcr.io`) | **PARAMETERIZE namespace** → `${IMAGE_NS:-mopro}/…`; **flag**: wrong registry vs CI (Docker Hub, not ghcr) — pre-existing, separate from the namespace fix → Backlog |
| `docs/runbooks/launch-day.md:154` | `docker images ghcr.io/salihsefer36/mopro-core-svc` | **DRIVE-BY FIX** — doubly stale: owner is `s4l1hs` (not `salihsefer36`), image is `core-svc` (not `mopro-core-svc`) |
| `docs/deploy.md:15-16` | explains owner-relative namespace | **UPDATE** — add `IMAGE_NS` usage (§3.3) |
| `docs/deploy.md:41-42` | hotfix example, `ghcr.io/<owner>/` placeholder | leave (already placeholder) |
| `CONTRIBUTING.md:741,771-772` | owner-relative explanation + `<owner>` hotfix example | **UPDATE** — add IMAGE_NS pattern (§5) |
| `PROMPTS.md:15` | "`ghcr.io/mopro/<binary>` is the canonical image namespace" | leave — descriptive of canonical/org end-state; `mopro` default keeps it accurate |
| `INFRASTRUCTURE.md:250` | tag-scheme doc `ghcr.io/mopro/<binary>:<semver>` | leave — descriptive/canonical |
| `SYSTEM_AUDIT.md:800` | audit description of image build | leave — historical record |
| `.github/workflows/build-images.yml:7-10,47` | pusher comments + owner-relative ns logic | leave — non-goal (no CI changes); already owner-relative + correct |
| `REPORT.md` (5 lines), `tool/audit/*.md` | historical audit/report entries | leave — records |

## §2.2 — CI push target
`build-images.yml` pushes owner-relative (`ghcr.io/${owner,,}` = `ghcr.io/s4l1hs`).
Correct as-is; this PR matches the puller to it via `IMAGE_NS`.

## §2.3 — Compose files present
- `deploy/docker-compose.yml` — dev/launch, **ghcr.io** registry (parameterized here).
- `deploy/docker-compose.prod.yml` — prod, **Docker Hub** registry `mopro/*`
  (namespace parameterized; registry discrepancy flagged → Backlog, not fixed here).
No other `docker-compose*.yml` / `compose.yml` outside `deploy/` reference the
project namespace (the test/e2e infra in the Makefile uses `docker run` with
stock images: postgres/redis/etc.).

## Note: deploy host is real
`docs/runbooks/launch-day.md:151` shows `ssh -p 4625 mopro@195.85.207.92`,
`/opt/mopro`. Host execution (setting `IMAGE_NS`, the actual pull) remains the
user's action — Claude Code has no SSH creds here.
