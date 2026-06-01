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

**Registry namespace is owner-relative** — `ghcr.io/<repo-owner>/<service>`. Under
the `mopro` org this is `ghcr.io/mopro/<service>` (what `deploy/docker-compose.yml`
pins). When the repo lives under a different owner (e.g. a fork), images push to
that owner's namespace instead; point the host pull at the matching namespace or
override the compose `image:`/`VERSION` refs.

## Rolling a build out to a host (manual)

Building + pushing does **not** deploy. To roll a new image onto a host:

```sh
# On the deploy host (from the compose dir, e.g. /opt/mopro):
sudo docker compose pull core-svc        # or fin-svc / jobs-svc / all
sudo docker compose up -d core-svc
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
