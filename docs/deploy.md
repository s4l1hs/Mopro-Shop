# Deploying backend services

## Image builds (automatic)

Backend service images build + push automatically on every `main` push via
[`.github/workflows/build-images.yml`](../.github/workflows/build-images.yml)
(also runnable on demand via `workflow_dispatch`). Each of `core-svc`, `fin-svc`,
`jobs-svc` is built from the single parameterized [`build/Dockerfile`](../build/Dockerfile)
(`--build-arg SERVICE=<svc>`, mirroring `make docker-build`) and pushed with three tags:

- `:latest`
- `:<full-sha>`
- `:<short-sha>` (8 chars)

**Registry namespace is owner-relative** — the workflow pushes to
`ghcr.io/<repo-owner>/<service>`, i.e. `ghcr.io/s4l1hs/<service>` on the current
fork and `ghcr.io/mopro/<service>` if/when the repo migrates to the `mopro` org.

**`IMAGE_NS` now defaults to `s4l1hs`** (F-DH-1). `deploy/docker-compose.prod.yml`
pulls `ghcr.io/${IMAGE_NS:-s4l1hs}/<service>` and `deploy.yml` passes
`IMAGE_NS=<repository_owner>` through to the deploy script, so namespace alignment
is automatic. If the repo migrates to the `mopro` org, flip the default + the
workflow follows the owner automatically. (The dev `deploy/docker-compose.yml`
keeps `:-mopro`; it is no longer reachable from the deploy path, which targets
the prod file explicitly with `-f`.)

**Registry login is mandatory (F-DH-1 §3.4).** The `ghcr.io/s4l1hs/*` packages
are private; the deploy script logs in before pulling, reading two keys from the
host's compose-dir `.env` (symlink → `/etc/mopro/.env`, root-only):

```sh
# One-time host prep — PAT scope: read:packages ONLY.
echo 'GHCR_USER=<github-user>' | sudo tee -a /opt/mopro/deploy/.env > /dev/null
echo 'GHCR_PAT=<pat>'          | sudo tee -a /opt/mopro/deploy/.env > /dev/null
```

Without these keys the deploy **fails fast with instructions** — that is correct
behavior, not a bug. (Alternative: make the three packages public on GitHub and
the login becomes a no-op safety net.)

## Deploying via the `deploy` workflow (canonical)

`workflow_dispatch` → `.github/workflows/deploy.yml` scps a fresh
`deploy/docker-compose.prod.yml` + `tool/audit/deploy_script.sh` to the host and
runs the script, which: logs into GHCR → `compose pull` (fail-fast) → `up -d` →
bounded `/healthz` wait → **asserts each running container's image ID equals the
freshly pulled ref** (a green no-op deploy is impossible) → prints a deploy
summary. `verify_only=true` exercises ssh/scp/login/config without pull/up.

**Migrations are NOT part of the deploy script.** When a release includes new
migrations, apply them BEFORE dispatching the deploy (additive-first ordering):

```sh
./deploy/scripts/apply-migration.sh --db ecom status   # then: up
./deploy/scripts/apply-migration.sh --db ledger status # then: up
```

## Rolling a build out to a host (manual fallback)

Building + pushing does **not** deploy. Prefer the workflow above. By hand:

```sh
# On the deploy host (compose dir /opt/mopro/deploy):
sudo docker login ghcr.io -u "$GHCR_USER"   # paste the read:packages PAT
sudo IMAGE_NS=s4l1hs docker compose -f docker-compose.prod.yml pull core-svc
sudo IMAGE_NS=s4l1hs docker compose -f docker-compose.prod.yml up -d core-svc
```

If watchtower (or a similar auto-pull agent) is configured on the host, this
happens automatically when `:latest` updates. Wiring up that auto-pull is a
Backlog item; today rollout is a manual step on each backend change.

## Manual / out-of-band build (hotfix, debug)

To get a backend change onto a host without a `main` merge:

```sh
docker build --platform=linux/amd64 --build-arg SERVICE=core-svc \
  -t ghcr.io/<owner>/core-svc:hotfix-<short_sha> -f build/Dockerfile .
docker push ghcr.io/<owner>/core-svc:hotfix-<short_sha>
# then on the host: docker compose pull && docker compose up -d core-svc
```

Keep `:latest` reserved for the `main`-built image — don't push custom tags to `:latest`.
