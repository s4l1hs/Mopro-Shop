# Discipline-Arc Close + Deploy — Baseline

Branch `chore/close-discipline-arc-and-deploy`. Base `main@7b8d96cc` (PR #49 merged 2026-06-02T08:12:49Z).

> **Ownership note.** This prompt is mixed-ownership. The sections below are
> partitioned into **[CLAUDE-VERIFIED]** (read-only facts gathered from git +
> the GitHub API) and **[HOST — USER ACTION]** (anything requiring SSH into the
> deploy host or `docker compose exec`). Claude Code has **no SSH/host access in
> this environment**, so every host-side check is marked NOT-DONE and is the
> user's to run + report back. Nothing below was fabricated from an unreachable host.

---

## Three corrections to the prompt's assumptions (surfaced before §3)

1. **The required status-check context is `verify`, NOT `make-verify`.** The
   workflow file is *named* `make-verify` (`name: make-verify`), but branch
   protection keys on the **job/check-run name**, and the job is `jobs.verify`
   with no `name:` override. Confirmed against `main@7b8d96cc`'s check-runs:
   the gate appears as `verify` (the three image builds appear as
   `build (core-svc|fin-svc|jobs-svc)`). Searching for `make-verify` in the
   branch-protection dropdown will not match the real check. **Require `verify`.**

2. **`main` has NO branch-protection rule at all.** `GET …/branches/main/protection`
   → `404 Branch not protected`. So §3's "find the rule for main, click Edit" does
   not apply — a rule must be **created**. (Claude Code has repo `admin`, so this
   can alternatively be applied directly via `gh api PUT …/protection` — offered to
   the user as a faster, less-error-prone path than the UI.)

3. **Registry-namespace mismatch blocks a naive host pull under this owner.**
   CI (`build-images.yml`) pushes owner-relative → `ghcr.io/s4l1hs/<svc>` (repo is
   `s4l1hs/Mopro-Shop`). But `deploy/docker-compose.yml` pins `ghcr.io/mopro/<svc>`
   and `deploy/docker-compose.prod.yml` pins Docker Hub `mopro/<svc>`. There is **no
   env-based namespace override** (only `VERSION`). `docs/deploy.md` §"Registry
   namespace" documents this: under a non-`mopro` owner you must repoint the host
   pull or edit the compose `image:` refs. So §5's plain `docker compose pull`
   will 404 the `ghcr.io/mopro/*` tags unless the host genuinely operates under the
   `mopro` org (separate from this GitHub fork) or its compose is already repointed.
   **Cannot be resolved without host access — user must confirm the host's actual
   image namespace.**

---

## §2.1 — PRs merged to `main` (recent history) — [CLAUDE-VERIFIED]

| PR | Merged | Merge SHA | Title | Backend src? | build-images run |
|----|--------|-----------|-------|--------------|------------------|
| #49 | 06-02 | `7b8d96cc` | identity user-state-consumer guard | yes (internal/identity) | run 26807227829 ✅ |
| #48 | 06-02 | `8bfb224a` | revive cart+identity integration suites | tests only (build fired) | run 26805199638 ✅ |
| #47 | 06-02 | `9201cba4` | financial pool discipline | yes (internal/wallet) | run 26801636886 ✅ |
| #46 | 06-02 | `802bfed9` | REPORT.md update | **docs-only** | none (path-filtered — expected, not a gap) |
| #44 | 06-02 | `68b798ce` | CI: install ImageMagick 7 in make-verify | CI yaml only | (workflow-file change) ✅ |
| #43 | 06-02 | `2daf991f` | wallet GetSystemState tx routing | yes (internal/wallet) | run 26800356879 ✅ |
| #42 | 06-01 | `a67dcf69` | cashback pgxpool deadlock | yes (internal/cashback) | run 26780337275 ✅ |
| #41 | 06-01 | `8b6d9fec` | **CI infra: image-build + make-verify** | adds build-images.yml | run 26774641377 ✅ (first build) |
| #40 | 06-01 | `9efd35bc` | revive internal/e2e suite | tests | (pre-#41 merge; first captured by #41's build) |

**Key fact:** `build-images.yml` did not exist until PR #41 (`8b6d9fec`, 2026-06-01).
The first successful build ran on #41's merge and captured the full tree at that
point (incl. #40). Every backend-touching merge since has a green build. Therefore
the image at **`<owner-ns>/<svc>:7b8d96cc`** (main HEAD) contains **all merged
backend code through #49** — a single rollout to that tag closes the entire deficit.

## §2.2 — Image-build workflow status per merge — [CLAUDE-VERIFIED]

All 6 recent `main`-push build runs **succeeded** (`gh run list --workflow=build-images.yml`):
`7b8d96cc, 8bfb224a, 9201cba4, 2daf991f, a67dcf69, 8b6d9fec` → all `success`.
The check-runs on `7b8d96cc` show `build (core-svc)`, `build (fin-svc)`,
`build (jobs-svc)` all `success` with `push: true`. No backend-touching merge is
missing a build. PR #46 (docs-only) correctly did not trigger one.

*Caveat:* the local `gh` token lacks `read:packages` scope (`GET /users/s4l1hs/
packages/container/core-svc/versions` → 403), so the pushed **tag list** could not
be enumerated directly. The green `build (*)` check-runs + `push: true` are the
evidence that `:latest`, `:7b8d96cc…`, and `:<short_sha>` were pushed under
`ghcr.io/s4l1hs/`.

## §2.3 — Currently-deployed image vs main — [HOST — USER ACTION — NOT DONE]

Requires SSH to the deploy host. Run there and paste back:
```sh
sudo docker compose images core-svc fin-svc jobs-svc
sudo docker compose ps core-svc fin-svc jobs-svc
# image SHA label (only if build/Dockerfile sets it; otherwise read the :TAG):
sudo docker image inspect <ns>/core-svc:latest --format '{{.Created}} {{.Id}}'
```
The gap between the deployed SHA and `main` HEAD (`7b8d96cc`) is the rollout deficit.
**Unknown until the host reports.**

## §2.4 — Current branch-protection state — [CLAUDE-VERIFIED]

`GET repos/s4l1hs/Mopro-Shop/branches/main/protection` → **404 "Branch not protected"**.
No rule exists; no required status checks. (See correction #2 above.) Repo viewer
permission: `admin: true` (so the rule can be applied via API).

## §2.5 — Storage provisioning state — [HOST — USER ACTION — NOT DONE]

Requires `docker compose exec` on the host. Run there and paste back:
```sh
sudo docker compose exec core-svc env | grep -E '^(STORAGE|CDN_BASE_URL)='
```
§6 is ready only if `STORAGE_ENABLED=true` + the 4 `STORAGE_*` creds +
`CDN_BASE_URL` are all set. **Unknown until the host reports.** (Per memory
`project_photo_consumer_blocked`, this was the open ops-provisioning gate.)

---

## What Claude Code can / cannot do this turn

- **Can:** the full read-only audit above; apply the branch-protection rule via
  `gh api` (has admin) if the user opts in; verify the rule post-application;
  the post-rollout SHA comparison *once the host reports its deployed tag*.
- **Cannot (no host access):** §2.3, §2.5, §5 (host pull/restart/health), §6.1
  (storage env + live `POST /uploads/photos` smoke). These are user-executed.
