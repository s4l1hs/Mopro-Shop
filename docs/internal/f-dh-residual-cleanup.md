# F-DH-RESIDUAL Discovery — Legacy Deploy-Path Retirement (§2)

> Closes the residual behind the no-op-deploy saga (#104 → #105 → #106): the tarball path that
> tagged local `mopro/<svc>` images. Repo + live-host evidence, 2026-06-07.

## 1. Canonical-path confirmation

The canonical deploy is PR #105's `deploy.yml` → `tool/audit/deploy_script.sh` →
`-f docker-compose.prod.yml` pulling `ghcr.io/s4l1hs/*` (merged; #106 ACME fix merged on top).
Retiring the tarball path orphans nothing in that chain — `deploy.yml` never touches
`deploy/scripts/deploy.sh`.

## 2. Reference map (everything that names the legacy path)

| Ref | Kind | Action |
|---|---|---|
| `deploy/scripts/deploy.sh` (143 ln) | the script: scp tarballs → `docker load` → tag `mopro/<svc>:latest` → rolling restart | **DELETE** |
| `deploy/scripts/rollback.sh` (50 ln) | loads `bin/prev/*.tar` — tarball-only; dead without deploy.sh | **DELETE** |
| `Makefile` `release:` (saves `mopro/*` tarballs to bin/), `deploy:`, `deploy-staging:`, `rollback:` + the help list (L27) | targets calling the deleted scripts | **DELETE targets** |
| `Makefile` `docker-build:` | tags `mopro/<svc>:$(VERSION)` — the last in-repo `mopro/*` tagger; used by nothing but `release` (CI builds via build-push-action) | **RETAG** to `ghcr.io/$(IMAGE_NS)/…`, `IMAGE_NS ?= s4l1hs` (keeps the local-build helper, kills the mopro tag) |
| `deploy/RUNBOOK.md` (Day-0 `make deploy`, routine `make deploy`/`make rollback`, Known-quirks "docker load pattern" row) | operator doc | **UPDATE** to workflow + pinned-VERSION rollback |
| `docs/runbooks/launch-day.md` §Option B (`rollback.sh`) | incident lever | **UPDATE** |
| `docs/runbooks/daily-cashback-payout-complete.md`, `docs/runbooks/checkout-abandonment-spike.md` (`make rollback`) | incident levers | **UPDATE** |
| `DISASTER_RECOVERY.md` §5.4 (`./scripts/deploy.sh "$(cat .previous-tag)"`) | DR doc | **UPDATE** |
| `docs/ops/backups.md` L59, `deploy/scripts/install-backup.sh` L3, `install-disk-watch.sh` L3 ("after deploy.sh has…") | comment-level attributions | **REWORD** (the /opt/mopro layout stands; only the attribution is stale) |
| `SYSTEM_AUDIT.md`, `docs/audits/TOOLING_AUDIT.md`, `docs/launch/L9-*`, `docs/internal/*`, `REPORT.md` history | point-in-time audit/history records | **LEAVE** (historical; rewriting audits falsifies the record) |

Nothing else (CI, cron, backup units) invokes the scripts: `install-backup.sh`/`install-disk-watch.sh`
only *mention* deploy.sh in comments; `build-images.yml` references `make docker-build` in a comment
(still true post-retag). No §5 carve needed — neither script is load-bearing elsewhere.

**Replacement rollback story** (since `make rollback` dies): GHCR keeps `:<full-sha>` tags
(build-images.yml), so rollback = re-run the pinned previous build on-host:

```sh
sudo IMAGE_NS=s4l1hs VERSION=<previous-full-sha> \
  docker compose -f /opt/mopro/deploy/docker-compose.prod.yml up -d core-svc fin-svc jobs-svc
```

DEFER (pipeline change, out of scope here per anti-goal 1): add a `version` input to `deploy.yml`
so rollback is a workflow dispatch too.

## 3. Host state (read-only, 2026-06-07) — PURGE GATE

```
core-svc  mopro/core-svc:latest      ← RUNNING
fin-svc   mopro/fin-svc:4e73f25      ← RUNNING
jobs-svc  mopro/jobs-svc:4e73f25     ← RUNNING
ghcr.io/* images on host: (none)
```

**Purge precondition FAILED → §3.3 STOPPED per §7-4 (Outcome C for the host-op half).**
Prod still runs the stale 2026-05-26 `mopro/*` build — the #105-repaired pipeline is merged but
the host-prep (GHCR PAT) + re-deploy haven't been executed yet. This is the *known* deploy gap
from #104, not a new one. Forcing the purge would delete the images prod is running on.

Inventory recorded for the post-deploy purge (one guarded op once prod is on `s4l1hs`):
- **59 `mopro/*` images** (~35 GB docker total, ≈1.1 GB reclaimable per `docker system df`;
  many tags share layers). In-use IDs to exclude until after the flip: `16d4cce92b11`
  (core `:latest` + `:9fb19c1`), `9b10507e77be` (fin `:4e73f25`), `ef7bd610ca63` (jobs `:4e73f25`).
- **`/opt/mopro/bin/*.tar`** legacy tarballs (≈340 MB+, May 20–26) + `bin/prev/` — tarball-path
  artifacts; outside §3.3's image-only scope, listed in the RUNBOOK purge procedure as a
  follow-on `rm` once the same gate passes.

## 4. Resolver state (§3.4 gate)

`/etc/resolv.conf` = single `nameserver 8.8.8.8`; plain static root-owned file, mtime Jan 19;
**systemd-resolved inactive, NetworkManager inactive** → not provisioner-managed; hand-edit is
the management mechanism on this host. Caveat: a `dhclient` process runs, but the file's 5-month-old
mtime proves it isn't rewriting resolv.conf; if a future lease renewal ever does, the durable form
is `supersede domain-name-servers …;` in `/etc/dhcp/dhclient.conf` (documented in RUNBOOK).
Plan: append `1.1.1.1` + `9.9.9.9` (host-wide complement of #106's caddy-only `dns:` fix).

## 5. Execution order

1. Commit 1: this doc. 2. Commit 2: delete scripts + Makefile targets + retag `docker-build`.
3. Commit 3: doc updates (RUNBOOK incl. post-deploy purge procedure, runbooks, DR, backups, REPORT).
4. Host op: resolver hardening (gate passed). 5. Host op: image purge — **deferred to post-deploy**
   (gate failed; procedure shipped in RUNBOOK). 6. gitleaks + `make verify` (confirms no orphaned
   targets) + PR.
