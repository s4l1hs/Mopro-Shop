# Reconcile Prod Registry — Baseline + Decision

Branch `chore/reconcile-prod-registry`. Base `main@53ea1c57` (PR #51 merged).

## The mismatch (plain English)
**CI pushes to GHCR; prod pulls from Docker Hub; nothing connects them.** PR #51
parameterized the *namespace* of both compose files via `IMAGE_NS`, but the prod
file is still a **bare Docker Hub** reference (no `ghcr.io/` prefix), so the
parameterization can't bridge the registry gap.

## §2.1 — Image references + push targets

| Source | core/fin/jobs ref | Registry | Namespace | Tags |
|---|---|---|---|---|
| `build-images.yml` (push) | `ghcr.io/${owner,,}/<svc>` → `ghcr.io/s4l1hs/<svc>` | **GHCR** | owner-relative (`s4l1hs`) | `:latest`, `:<sha>`, `:<short_sha>` |
| `deploy/docker-compose.yml` (dev pull) | `ghcr.io/${IMAGE_NS:-mopro}/<svc>:${VERSION:-latest}` | **GHCR** | `${IMAGE_NS:-mopro}` | `:${VERSION:-latest}` |
| `deploy/docker-compose.prod.yml` (prod pull) | `${IMAGE_NS:-mopro}/<svc>:${VERSION:-latest}` | **Docker Hub** ⚠ | `${IMAGE_NS:-mopro}` | `:${VERSION:-latest}` |

The dev compose already matches CI (GHCR). Only `.prod.yml` diverges — on the
**registry**, not the namespace.

## §2.1 — Docker Hub credential / org status
- **`gh secret list` → empty.** No `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` (or any
  repo Actions secret). `build-images.yml` authenticates only with the
  auto-provided `secrets.GITHUB_TOKEN` (GHCR). **Docker Hub push was never wired.**
- **Docker Hub `mopro` namespace:** `/v2/orgs/mopro/` → HTTP 200 (the namespace is
  claimed on Docker Hub), but `/v2/repositories/mopro/core-svc/` → **404** (no image
  ever pushed there). No evidence this account controls that `mopro` namespace.

## §2.1 — Other operational refs (cross-checked vs PR #51 audit)
Already reconciled by PR #51: `deploy/docker-compose.yml`, `docs/deploy.md`,
`docs/runbooks/launch-day.md`, `CONTRIBUTING.md`. `PROMPTS.md`/`INFRASTRUCTURE.md`/
`SYSTEM_AUDIT.md` are descriptive-canonical (left as-is). No *new* drift surfaced
beyond the prod-registry one this PR targets.

## §2.2 — Decision: **Option A — point `.prod.yml` at GHCR**
User-selected (AskUserQuestion). Rationale:
- GHCR is CI's actual, working output (images exist + green builds through #49).
- Docker Hub has **no credentials, no pushed repo, unverified org ownership** —
  Option B would require provisioning all three before it could even build.
- Matches the dev compose + PR #51's `IMAGE_NS` pattern exactly → both compose
  files become registry- and namespace-consistent.

Fix: `${IMAGE_NS:-mopro}/<svc>` → `ghcr.io/${IMAGE_NS:-mopro}/<svc>` (add the GHCR
prefix; namespace parameterization unchanged). The Docker Hub `mopro` namespace is
left reserved-but-unused — a no-op (Option A risk note).
