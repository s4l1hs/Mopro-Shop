# Deploy Health Discovery — DEPLOY-HEALTH-01 (§2)

> Pre-diagnosis topology snapshot, derived from source only (no host contact yet).
> Date: 2026-06-07. Companion to `docs/audits/PRODUCTION_DEPLOY_HEALTH.md`.

## 1. Deploy topology (`deploy/docker-compose.prod.yml`)

Compose project `mopro`, run from the host compose dir (discovered at runtime by
`tool/audit/deploy_script.sh`: `/opt/mopro/deploy` → `/opt/mopro` → find). `.env` is a
symlink to `/etc/mopro/.env` (deploy.sh §0).

| Service | Image | Host ports | Healthcheck | Notes |
|---|---|---|---|---|
| postgres-ecom | postgres:16-alpine | — | pg_isready | 5g/2.0cpu |
| postgres-ledger | postgres:16-alpine | — | pg_isready | 3g/1.5cpu, mopro-fin-net (internal) |
| postgres-config | postgres:16-alpine | — | pg_isready | stub (OQ-C), nothing connects |
| init-passwords | postgres:16-alpine | — | — | one-shot (`restart: "no"`); Exited(0) is normal |
| pgbouncer-ecom | edoburu/pgbouncer | — | nc :5432 | |
| pgbouncer-ledger | edoburu/pgbouncer | — | nc :5432 | fin-net |
| redis | redis:7-alpine | — | redis-cli ping | both nets |
| meilisearch | getmeili/meilisearch:v1.6 | — | curl /health | |
| caddy | caddy:2.8-alpine | 80, 443, 443/udp | nc :80 | reverse proxy + TLS |
| core-svc | ghcr.io/${IMAGE_NS}/core-svc:${VERSION} | 127.0.0.1:8080 | **disabled** (distroless) | |
| fin-svc | ghcr.io/${IMAGE_NS}/fin-svc:${VERSION} | 127.0.0.1:8081 | **disabled** | dual-homed |
| jobs-svc | ghcr.io/${IMAGE_NS}/jobs-svc:${VERSION} | 127.0.0.1:8082→8080 | **disabled** | 1200m mem |
| grafana-agent | grafana/agent:latest | — | — | ships to Grafana Cloud |

- Go services: distroless, `healthcheck: disable: true` → Docker health is N/A for them;
  health is HTTP `/healthz` probed from the host.
- **Port mapping caveat:** `tool/audit/deploy_script.sh` (the script the deploy workflow
  actually runs) asserts "the services publish NO host ports — only Caddy exposes :80"
  and probes everything through Caddy `http://localhost/...`. The compose file in-repo
  maps `127.0.0.1:8080/8081/8082`. **Resolve live**: try direct ports first, fall back
  to Caddy-routed paths.
- `IMAGE_NS=s4l1hs` is set in the compose-dir `.env` by deploy_script.sh STEP 1
  (ghcr.io/s4l1hs/*; the compose default `mopro` is overridden — known namespace
  mismatch, see reference_ci_deploy_facts).

## 2. Ingress / public URLs (`deploy/caddy/Caddyfile`)

- **Public API base: `https://api.moproshop.com`** → core-svc:8080 default;
  `/wallet/* /cashback/* /payouts/* /admin/*` → fin-svc:8081; `/jobs/*` → jobs-svc:8080.
- `/healthz` on every site block is **Caddy-native** (`respond "OK" 200`) — it proves
  ingress only, NOT backend health. Backend health = `/healthz` on each service port,
  or any proxied route.
- Other blocks: seller.moproshop.com → core-svc; moproshop.com/www → static "Çok yakında";
  admin.moproshop.com → static 503; fin.moproshop.com → static 404; staging blocks exist.
- `localhost:80` block (plain HTTP, on-host): `/healthz` native + same routing — this is
  what deploy_script.sh uses.
- CloudFlare-only enforcement is still TODO (commented out) — direct IP access is NOT
  rejected yet, contrary to CLAUDE.md §3.5 intent. Pre-existing, not a regression.

## 3. Health + version endpoints (from `cmd/*/main.go`)

| Service | Path | Where |
|---|---|---|
| core-svc | `GET /healthz`, `GET /__version` | cmd/core-svc/main.go:398,401 |
| fin-svc | `/healthz` | cmd/fin-svc/main.go:303 |
| jobs-svc | `/healthz` | cmd/jobs-svc/main.go:121 |

`/__version` (core-svc) returns the built SHA — primary deployed-SHA cross-check.

## 4. Smoke targets (from `api/openapi.yaml`)

| # | Target | Method + path | Pass criterion |
|---|---|---|---|
| 1 | PDP delivery-ETA | `GET /products/{id}?dest_city=<city>` | 200; `delivery_eta` present + sane (P-034 table-driven; null allowed only if no estimate) |
| 2 | Filters | `GET /products?category_id=&min_price=&...` | 200; results narrow vs unfiltered |
| 3 | Bestseller sort | `GET /products?sort=bestseller[&category_id=]` | 200; ordered list (per-category PR #100; global-proxy fallback PR #99) |
| 4 | Card badges | `GET /products` → `ProductSummary` | `original_price_minor` / `discount_pct` present on a discounted item; visual = manual |
| 5 | Auth gate | `GET /products` unauth vs `POST /cart/items` unauth | 200 guest read; 401 gated write |

Discovery shift: there is **no `/favorites` route** in openapi.yaml — the auth-gated
action check uses `POST /cart/items` (or `/orders/checkout`) instead.

## 5. Metrics + vuln

- **No local Prometheus server.** grafana-agent scrapes `:9100/:9101/:9102` and remote-writes
  to Grafana Cloud. No on-host query API ⇒ p95/5xx-rate via PromQL is **not SSH-accessible**;
  plan: scrape raw `/metrics` counters directly (bridge-network IP or expose'd port) for a
  point-in-time 5xx/total ratio, and mark dashboard-level p95 **manual-verify** (Grafana Cloud UI).
- Vuln status: `.github/workflows/govulncheck.yml` — required gate, weekly + per-PR; read the
  latest run conclusion via `gh run list --workflow=govulncheck.yml`.

## 6. Migration state (read-only method)

golang-migrate per cluster: `SELECT version, dirty FROM schema_migrations` —
`docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c ...` (and ledger equiv).
Latest in repo: ecom **0085** (shipping_zones), ledger **0080** (sellerpayout_schema_split).

## 7. Deploy mechanics (what run 27087000549 did)

`deploy.yml` = workflow_dispatch → scp `tool/audit/deploy_script.sh` to host → run it.
Script: discovers compose dir, sets `IMAGE_NS=s4l1hs`, `compose pull` + `up -d` the three
Go services (SKIPPED when `VERIFY_ONLY=true` — the workflow's **default**), then health via
Caddy `localhost/healthz` + `/__version`, error-grep of last 80 log lines, storage-env dump,
optional photo-upload smoke. NOTE: script's `EXPECTED_SHA_PREFIX=7b8d96cc` is stale (PR #49 era);
do not treat its mismatch warning as a failure — cross-check `/__version` against the run's
actual built SHA instead.

## 8. Verification plan (order of operations)

1. `gh run view 27087000549` — green? `verify_only` input? built image SHA.
2. SSH (mopro@195.85.207.92:4625): `docker compose ps`, `docker inspect` restart counts,
   `df -h`, `free -m`, uptime.
3. `/healthz` ×3 (direct port or Caddy), `/__version` SHA vs run SHA.
4. Five smoke targets through Caddy (localhost:80 or public domain).
5. Logs since deploy: `docker compose logs --since <deploy-time>` per service, error scan.
6. TLS: `curl -vI https://api.moproshop.com/healthz` cert expiry; govulncheck via gh;
   schema_migrations per cluster.
7. Remediation only per §3.6 protocol if something is down. Report last.
