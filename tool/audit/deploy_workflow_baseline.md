# Deploy Workflow — Baseline + Path-Discovery Failure Analysis

Branch `chore/add-deploy-workflow`, based on `chore/deploy-accumulated-main-and-verify`
(the predecessor that introduced `tool/audit/deploy_script.sh`; never PR'd → this PR
supersedes it). Base content reaches back to `main@f1b53dac` (PR #52).

## §2.1 — The compose-path failure

**Provenance:** reported by the user from an out-of-band host session — **not
observed by Claude Code** (no script output was pasted back from the prior
deploy-verify turn). Recorded as the user's report.

- **What the script assumed:** `cd /opt/mopro || { echo FATAL; exit 1; }` then every
  `docker compose` call relative to `/opt/mopro`.
- **What the failure proved (per report):** `/opt/mopro` exists (the `cd` succeeded)
  but holds **no `docker-compose*.yml`** → `docker compose` returned "no configuration
  file provided: not found." The compose file is elsewhere (likely `/opt/mopro/deploy/`,
  mirroring the repo's `deploy/docker-compose.yml` layout — but the host could differ).
- **Independent corroboration that the assumption is fragile:** the two in-repo
  sources of truth disagree on the compose location —
  - `docs/runbooks/launch-day.md` does `cd /opt/mopro` then `docker compose up` →
    implies `/opt/mopro/docker-compose.yml`.
  - the repo keeps compose at `deploy/docker-compose.yml`.
  Whichever the host uses, a hard-coded single path is wrong for the other. **Auto
  discovery (env override → known paths → `find` fallback) is correct regardless of
  which report is literally true.** → §3.

- **Secondary bug:** the prior script wrote `IMAGE_NS=s4l1hs` to `/opt/mopro/.env`,
  but Docker Compose reads `.env` from the **compose file's directory**. If compose is
  at `/opt/mopro/deploy/`, the IMAGE_NS write landed in the wrong `.env` and never took
  effect. §3 writes it to `$COMPOSE_DIR/.env`.

## §2.2 — `build-images.yml` precedent (closest workflow pattern)
- **Trigger:** `workflow_dispatch` + `push` on `main` (path-filtered).
- **Auth:** `secrets.GITHUB_TOKEN` for GHCR (no external secret).
- **Run:** matrix per service (core/fin/jobs), `docker/build-push-action@v5`.
- **Runtime:** ~2m14s for the last run (08:12:53→08:15:07).
- The deploy workflow follows the same house style but differs on trigger
  (`workflow_dispatch`-only — no auto-deploy) and auth (SSH key, not `GITHUB_TOKEN`).

## §2.3 — Current repo secrets
`gh secret list` → **empty**. No conflicts. The three new secrets
(`DEPLOY_SSH_KEY`, `DEPLOY_HOST`, `DEPLOY_PORT`) are net-new (user-provisioned, §4).

## §2.4 — Gaps in the prompt's plan (surfaced before provisioning)
1. **`NOPASSWD` sudo is a hard prerequisite.** The workflow runs
   `ssh host "sudo … bash deploy_script.sh"` non-interactively and the script calls
   `sudo docker compose`. No TTY in CI → a sudo password prompt hangs the job. The
   deploy user must have passwordless sudo (at least for `docker`/the script).
2. **The smoke test is a real prod deploy.** `deploy_script.sh` steps 2–3 do
   `docker compose pull` + `up -d` — running the workflow restarts prod containers,
   contradicting the non-goal "no production deploy execution in this PR." → §3 adds a
   `VERIFY_ONLY` mode (SSH + scp + discovery + `compose config`, **no** pull/up) so the
   plumbing can be verified non-destructively; the workflow defaults its `verify_only`
   input to **true**.

## §2.5 — Security surface (for REPORT risk notes; implementing, not refusing)
This is the user's own authorized deploy host; CI deploy is standard. Sharp edges to
flag, not block: passwordless SSH key in Actions secrets (anyone who can trigger the
workflow can deploy); `ssh-keyscan` TOFU on first connect (no fingerprint pinning —
prefer pinning the host key in a secret); `NOPASSWD` sudo widens blast radius if the
key leaks. All Backlog-worthy hardening, recorded in REPORT.
