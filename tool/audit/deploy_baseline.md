# Deploy Accumulated Main — Baseline + Rollout Manifest

Branch `chore/deploy-accumulated-main-and-verify`. Generated autonomously (§2).

## Rollout manifest

- **Main HEAD:** `f1b53dac7280f35ceabffe5e0964d51c2db41678` (short `f1b53dac`) — PR #52 merge.
- **Expected deployed IMAGE SHA: `7b8d96cc`** (NOT `f1b53dac`). ⚠️ This is the crux:
  the `build-images.yml` workflow is **path-filtered** (`cmd/**`, `internal/**`,
  `pkg/**`, `go.mod`, `go.sum`, `build/Dockerfile`, the workflow file). PRs
  **#50/#51/#52 touched only `deploy/**` + docs/CONTRIBUTING** → no image built for
  their SHAs (correctly). The last backend build is **PR #49 = `7b8d96cc`**. So:
  - `:latest` == the `7b8d96cc` build.
  - The `f1b53dac` changes (compose `image:` repoint, IMAGE_NS, docs) take effect on
    the host via the **compose file**, not via a new image.
  - core-svc `/__version` should report `sha` starting `7b8d96cc` after rollout.
    Do **not** expect an `f1b53dac` image tag — none exists.

### Image-build workflow status (latest 5, all `success`)
| createdAt | headSha | conclusion | PR |
|---|---|---|---|
| 2026-06-02T08:12 | `7b8d96cc` | success | #49 (last backend build → `:latest`) |
| 2026-06-02T07:29 | `8bfb224a` | success | #48 |
| 2026-06-02T06:02 | `9201cba4` | success | #47 |
| 2026-06-02T05:27 | `2daf991f` | success | #43 |
| 2026-06-01T20:33 | `a67dcf69` | success | #42 |

No build ran for `e0c2688e`(#50)/`53ea1c57`(#51)/`f1b53dac`(#52) — path-filtered, expected.

### GHCR tags (push evidence)
`gh` token lacks `read:packages` (403 listing versions), but the check-runs on
`7b8d96cc` show `build (core-svc)`, `build (fin-svc)`, `build (jobs-svc)` all
**success** with `push: true` → `ghcr.io/s4l1hs/<svc>:{latest,7b8d96cc…,<short>}` exist.

### PRs in this rollout (vs the pre-deploy image, which predates PR #34 per project memory)
All **backend** merges through #49 are baked into the `7b8d96cc` image: #34 (photo
upload backend), #38 (stack drain #31–#37), #40, #42, #43, #44, #47, #48, #49.
#50/#51/#52 are deploy-config/docs (land via the compose file on the host).
The pre-deploy STEP 0 output will reveal the host's *actual* current image to
confirm the true lower bound.

### Expected post-deploy state
- All three services **running** (`docker compose ps` State = Up/running).
- core-svc `/__version` → `{"sha":"7b8d96cc…", "service":"core-svc", …}`.
- `curl http://localhost/healthz` → `OK` (Caddy native).
- No `error|fatal|panic` in startup logs.

## Script-correctness notes (why this script ≠ the prompt's template)
The prompt's template script makes four assumptions that are wrong on this stack;
the generated `deploy_script.sh` corrects all four (so we don't waste the single
SSH round-trip):
1. **No host ports on svcs** — core/fin/jobs publish nothing; only Caddy exposes
   `:80/:443`. `docker compose port $svc 8080` returns empty. → Probe via Caddy's
   `localhost:80` block from the host instead.
2. **Distroless runtime** (`gcr.io/distroless/static-debian12:nonroot`) — no shell,
   no `nc`/`wget`/`curl`/`env`. → Read env with `docker inspect` (container config),
   not `docker compose exec core-svc env`. Health via host curl, not exec.
3. **Health route is `/healthz`, not `/health`; fin-svc is `:8081`.** SHA lives in
   core-svc `/__version` (ldflag `buildinfo.SHA`).
4. **`docker compose ps` Health may show `unhealthy`** even when fine — the compose
   healthcheck calls `nc -z`, which isn't in the distroless image (latent bug,
   Backlog). Trust State=Up + the `/__version` + `/healthz` host probes + logs over
   the Health column.
