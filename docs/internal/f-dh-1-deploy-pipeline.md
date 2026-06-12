# F-DH-1 Discovery — Deploy-Pipeline Repair (§2)

> Re-verification of the four defects filed in `docs/audits/PRODUCTION_DEPLOY_HEALTH.md` §3
> (PR #104), plus the image/registry/host facts the fix must align with. Source + live host
> evidence; date 2026-06-07.

## 1. Pipeline shape (current)

`deploy.yml` (workflow_dispatch) → sparse-checkout **only** `tool/audit/deploy_script.sh` →
scp to host `/tmp/deploy_script.sh` → ssh `mopro@host` runs it with `VERIFY_ONLY`/`SKIP_PHOTO_SMOKE`.
Nothing else is shipped to the host per deploy — compose files on the host are whatever the
**legacy** `deploy/scripts/deploy.sh` rsync'd last (≈ May 20). `deploy/scripts/deploy.sh`
(scp-tarball + `docker load` + rolling restart + rollback) is the superseded path; deploy.yml
does not use it.

## 2. The four defects — re-verified on branch

| # | PR #104 claim | Verdict | Evidence |
|---|---|---|---|
| ① | bare `docker compose` (no `-f`) → dev compose wins | **CONFIRMED** | `deploy_script.sh` `dc() { sudo docker compose "$@"; }`; host `/opt/mopro/deploy/` holds BOTH `docker-compose.yml` and `docker-compose.prod.yml`; bare compose auto-loads `docker-compose.yml`. Run 27087000549's `.env` warnings + `ghcr.io/mopro/*` pulls match the dev file, not prod. |
| ② | host compose hardcodes `ghcr.io/mopro/*`, no `${IMAGE_NS}` | **CORRECTED (partial)** | The **repo** dev AND prod composes both carry `ghcr.io/${IMAGE_NS:-mopro}/…` — the variable IS wired in-repo. Only the **host's stale dev copy** hardcodes `ghcr.io/mopro/<svc>` literally. The real gaps: (a) the `:-mopro` default names a **nonexistent** namespace; (b) the deploy_script path never refreshes compose files on the host; (c) the script's STEP-1 `IMAGE_NS` append is doubly broken — its existence-check `grep` runs unprivileged against root-only `/etc/mopro/.env` (always "missing" → re-appends every run; now duplicated ×2) and was inert anyway against the var-less host dev compose (F-DH-6). |
| ③ | no registry login on host | **CONFIRMED** | `/root/.docker/config.json` and `~mopro/.docker/config.json` both ABSENT (live, 2026-06-07). And the packages are **private**: anonymous GHCR pull-token request is denied; `GET /v2/s4l1hs/<svc>/manifests/latest` → 403 for all three. A `read:packages` PAT is required. |
| ④ | no `set -e` / SHA assertion | **CONFIRMED** | Script has `set -u` + `set -o pipefail` only; STEP 2's denied pull scrolls past; `EXPECTED_SHA_PREFIX=7b8d96cc` (PR #49-era, stale = F-DH-8) is printed, never asserted. |

Extra hazard found: dev and prod compose share `name: mopro` (same project) — an un-`-f`'d
`up -d` can adopt/recreate **prod** containers under dev config. `-f` targeting removes the class.

## 3. Image + registry facts

- `build-images.yml` pushes, on main pushes touching Go paths (`cmd/ internal/ pkg/ go.mod go.sum build/Dockerfile`):
  `ghcr.io/<owner,,>/<svc>:{latest, <full-sha>, <short-sha-8>}` with `BUILD_SHA` baked (surfaces at `/__version`).
- Current owner ⇒ `ghcr.io/s4l1hs/*`. Last build: main@`13aba07d` (2026-06-06, success ×3 services).
- **`:latest` may legitimately trail the deploy ref** — docs-only merges (e.g. #104 → `4d4a674b`)
  don't trigger builds. So the post-deploy assertion must be *"running container == freshly pulled
  `$IMAGE_NS/$svc:$VERSION` image"* (image-ID equality), NOT *"app SHA == deploy ref"*. `/__version`
  is printed as an audit line only (it already exists — no app change).
- Packages are **private** → host needs `docker login ghcr.io` with a `read:packages` PAT
  (`GHCR_USER` + `GHCR_PAT`). Alternative (Salih's call, not this PR): make the three packages
  public and drop the PAT requirement.

## 4. Host layout (live-verified in PR #104 + this session)

- Compose dir: `/opt/mopro/deploy` (script's discovery order finds it first). `.env` there is a
  symlink → `/etc/mopro/.env` (root:root 600) — already contains `IMAGE_NS=s4l1hs` (×2, from the
  broken append; harmless once the default is fixed, left in place — this PR stops the mutation
  but does not edit the secrets file).
- `mopro` user has effectively unrestricted passwordless sudo (live: `sudo grep`/`sudo cat`/
  `sudo test` all run non-interactive) — the workflow comment "sudo for docker/tee" undersells it;
  the script may safely `sudo grep` the env file for GHCR creds.
- Go services publish `127.0.0.1:8080/8081/8082` (prod compose) → direct `/healthz` waits are
  possible post-`up`; Docker healthchecks are disabled on the distroless services.
- **Migrations are NOT part of deploy_script.sh** (by design): `deploy/scripts/apply-migration.sh`
  (run from a dev machine) builds migrate-tool, scps it + `migrations/`, runs one-shot on the
  compose network. Prod is at ecom **62**/repo 0085, ledger **77**/repo 0080 — the runbook for the
  first repaired deploy must apply migrations **before** rolling new code (additive-first ordering).

## 5. Fix plan (maps to §3 commits)

1. **Fail-fast:** `set -euo pipefail`; every legitimate-failure line gets explicit `|| true`/handler;
   denied pull aborts the run.
2. **Targeting:** `dc()` pins `-f "$COMPOSE_DIR/docker-compose.prod.yml"`; compose-dir discovery
   requires the **prod** file; `deploy.yml` sparse-checks-out + scps `deploy/docker-compose.prod.yml`
   to `/opt/mopro/deploy/` each run (fresh, like the old rsync did).
3. **Namespace:** prod compose default → `ghcr.io/${IMAGE_NS:-s4l1hs}/…`; workflow passes
   `IMAGE_NS=<repository_owner>` (lowercased in script); STEP-1 .env append deleted (F-DH-6);
   `EXPECTED_SHA_PREFIX` deleted (F-DH-8). Dev compose untouched (its `:-mopro` default is now
   unreachable from the deploy path; changing it would ripple into local-dev/e2e builds).
4. **Login:** script extracts `GHCR_USER`/`GHCR_PAT` from the compose-dir `.env` via `sudo grep`,
   pipes `--password-stdin` to `sudo docker login ghcr.io`; missing keys or failed login = loud abort
   with provisioning instructions. PAT never echoed/logged.
5. **Assertion:** post-`up`, per service: image-ID of running container (`docker inspect …
   {{.Image}}`) must equal image-ID of the freshly pulled `ghcr.io/$IMAGE_NS/<svc>:$VERSION`;
   plus a bounded `/healthz` wait (200 on :8080/:8081/:8082) replacing `sleep 15`; mismatch or
   timeout → non-zero exit naming service + both IDs. Summary block prints ref + digest + `/__version`.

`VERIFY_ONLY=true` keeps its plumbing-only contract: login IS exercised (it's the most fragile
plumbing link), pull/up/assertion skipped.

## 6. Out-of-scope notes (carried, not fixed here)

- Auto-rollback on failed assertion — DEFER (deploy.yml stays fail-loud; `deploy/scripts/rollback.sh`
  remains the manual lever for the legacy path).
- `deploy/scripts/deploy.sh` legacy path left as-is — note it tags `mopro/<svc>` local images from
  tarballs, which the **repo's** prod compose (ghcr refs) already didn't match; that's how the host
  ended up running `mopro/core-svc:latest` against a host-pinned compose. Once the fresh-SCP'd prod
  compose lands on the host, the legacy tarball path is visibly incompatible (it always was with the
  repo) — retiring/aligning it is a DEFER follow-up, not silently "fixed" here.
- Host `/etc/mopro/.env` duplicate `IMAGE_NS` lines left as-is (secrets file untouched per anti-goals).
- F-DH-3 (Caddy ACME) — separate PR, sequenced after this.
