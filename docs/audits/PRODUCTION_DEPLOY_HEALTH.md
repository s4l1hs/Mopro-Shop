# Production Deploy Health Report — DEPLOY-HEALTH-01

> **Report date:** 2026-06-07 (UTC) · **Deploy run audited:** `27087000549` (deploy.yml, 2026-06-07 08:10 UTC)
> **Expected SHA (run head):** `13aba07d` (main, PR #103 merge) · **Actually running:** `9fb19c19` (built 2026-05-26)
> **Host:** VDS 195.85.207.92 (debian, 6 vCPU / 24 GB / 120 GB) · Method: read-only SSH diagnosis per DEPLOY-HEALTH-01 §3; no remediation actions taken.

---

## 1. Verdict — 🔴 RED · Path-B: **NO-GO**

| Axis | State | One-liner |
|---|---|---|
| Deploy | 🔴 FAIL | Run 27087000549 is green but **shipped nothing** — `compose pull` denied for all 3 images; production runs a build from **2026-05-26, 686 commits behind main** |
| Containers | 🟢 PASS | 12/12 up, 0 crash-loops (jobs-svc: 1 restart in 7 d), no OOM kills |
| Health endpoints | 🟢 PASS | `/healthz` 200 on core/fin/jobs + Caddy native + public `https://api.moproshop.com/healthz` |
| Smoke (5 targets) | 🔴 1/5 | Auth gate PASS; delivery-ETA / filters / bestseller / badges FAIL — **features post-date the running build** (merged 06-04→06-06), not code bugs |
| Metrics / logs | 🟢 PASS | 0×5xx since start; app logs spotless over 7 d; (Caddy ACME renewal noise — §6) |
| Security | 🟡 PASS* | govulncheck green; TLS valid to 2026-08-18; *cert-renewal path erroring + CloudFlare-only enforcement still TODO |

**Path-B readiness: NO-GO.** Path B refines surfaces (filters, badges, bestseller, ETA…) that are not running in production. Blocking item: **the deploy pipeline cannot ship images** (§3 root cause). Once a real deploy lands `13aba07d`+ and the 5 smoke targets pass, this flips to GO — the infrastructure itself is healthy.

---

## 2. Environment & topology

Full topology in `docs/internal/deploy-health-discovery.md`. Live confirmations / corrections:

- Compose project `mopro` at `/opt/mopro/deploy`; `.env → /etc/mopro/.env` (symlink, root-only).
- Go services **do** publish localhost ports (`127.0.0.1:8080/8081/8082`) — the deploy_script.sh comment claiming "no host ports" is stale.
- Public ingress: `https://api.moproshop.com` → Caddy → core-svc (fin/jobs path-routed). DNS resolves **directly to the VDS IP** (no CloudFlare proxying; the Caddyfile CF-only enforcer is still commented out).
- **Two compose files exist on the host** (`docker-compose.yml` dev + `docker-compose.prod.yml`), and they disagree on image refs — load-bearing for the root cause (§3).
- Running containers use `mopro/<svc>` local tags (docker-save/load era), created 2026-05-27, restarted 2026-05-31 (host reboot — explains uniform "Up 7 days").

## 3. Deploy verification — FAIL (green badge, nothing shipped)

Run `27087000549`: workflow_dispatch from main@`13aba07d`, `VERIFY_ONLY=false`, all steps "success", 36 s. The step log tells a different story:

```
===== STEP 2: DOCKER COMPOSE PULL =====
 Image ghcr.io/mopro/core-svc:latest Pulling
 Image ghcr.io/mopro/fin-svc:latest  error from registry: denied
 Image ghcr.io/mopro/jobs-svc:latest error from registry: denied
 Image ghcr.io/mopro/core-svc:latest error from registry: denied
```

STEP 4 `ps` shows every container untouched ("Up 7 days", created 11 days ago). STEP 5 `/__version` returned the **pre-deploy** SHA. Nothing was deployed; the badge is green only because `deploy_script.sh` has no `set -e` and no pull/SHA assertion.

**Root-cause chain (4 stacked defects):**

1. **Wrong compose file.** `deploy_script.sh` runs bare `docker compose` (its `dc()` helper has no `-f`), so Compose auto-loads `/opt/mopro/deploy/docker-compose.yml` — the **dev** compose — never `docker-compose.prod.yml`.
2. **Stale host copy, hardcoded namespace.** The host's dev compose (synced ≈ May 20) pins `ghcr.io/mopro/<svc>` **literally** — no `${IMAGE_NS}` variable (the repo has since moved to `ghcr.io/${IMAGE_NS:-mopro}/…`). The script's STEP-1 `IMAGE_NS=s4l1hs` append therefore changed nothing.
3. **No registry auth.** No `~/.docker/config.json` for root or mopro on the host — even the correct `ghcr.io/s4l1hs/*` refs would fail if those packages are private. (`ghcr.io/mopro/*` doesn't exist at all; CI pushes `ghcr.io/s4l1hs/*` — known mismatch, reference_ci_deploy_facts.)
4. **No failure propagation.** `set -u -o pipefail` but no `set -e` and no post-pull assertion (`/__version == expected SHA`), so the workflow reports success regardless. The script's own `EXPECTED_SHA_PREFIX=7b8d96cc` is also stale (PR #49 era) and isn't asserted.

Side-effects observed: `IMAGE_NS=s4l1hs` has been appended **twice** to `/etc/mopro/.env` (the script's existence check `grep` runs unprivileged against a root-only file → always "not set" → re-append each run). The deploy path also mutates the production secrets file as a matter of course — see F-DH-6.

**Staleness quantified:** running core-svc = `9fb19c19` ("fix(cart): seed Redis stock counters", 2026-05-26); fin/jobs = `4e73f254` ("Product Seeding", 2026-05-26). `git log origin/main --since=2026-05-26` = **686 commits** not in production, including the entire Step-5 parity arc (PRs #85–#103).

## 4. Container & resource health — PASS

| Container | Status | Restarts | Mem (used/limit) |
|---|---|---|---|
| caddy | Up 7d (healthy) | 0 | 62M / 256M |
| core-svc | Up 7d | 0 | 33M / 384M |
| fin-svc | Up 7d | 0 | 36M / 384M |
| jobs-svc | Up 7d | 1 | 13M / 1.17G |
| grafana-agent | Up 7d | 0 | **254M / 300M (85 %)** ⚠ |
| meilisearch | Up 7d (healthy) | 0 | 72M / 1.46G |
| pgbouncer-ecom / -ledger | Up 7d (healthy) | 0 / 0 | 2M / 5M of 128M |
| postgres-ecom / -ledger / -config | Up 7d (healthy) | 0 | 146M / 105M / 22M |
| redis | Up 7d (healthy) | 0 | 19M / 1.17G |
| init-passwords | Exited(0) | — | one-shot, by design |

No OOM kills; no crash loops. Host: disk 36 % (73 G free), RAM 1.3 G used / 24 G, load 0.14, up 7 d (reboot 2026-05-31 08:00 UTC).

## 5. Health endpoints + smoke checks

Health: `127.0.0.1:8080/8081/8082 /healthz` → **200/200/200**; Caddy-native `localhost/healthz` → 200; public `https://api.moproshop.com/healthz` → 200.

Smoke (via Caddy `localhost:80`, same routing as public; seeded data lives in category IDs 107–131, 50 active products):

| # | Target | Request | Expected | Actual | Verdict |
|---|---|---|---|---|---|
| 1 | PDP delivery-ETA | `GET /products/1?dest_city=diyarbakir` | 200 + `delivery_eta` object (P-034) | 200, **no `delivery_eta` field at all**; pre-#97 response shape | 🔴 FAIL (feature not deployed) |
| 2 | Filters | `GET /products?category_id=129&min_price=999999999` | empty result (narrowed) | **both products returned — filter param ignored**; also `category_id` is still mandatory (400 without it, pre-#85 contract) | 🔴 FAIL (feature not deployed) |
| 3 | Bestseller sort | `GET /products?category_id=129&sort=bestseller` | popularity-ordered | 200, param accepted but inert (no popularity projection in build; pre-#90/#99/#100) | 🔴 FAIL (feature not deployed) |
| 4 | Card badges | `ProductSummary` fields | `original_price_minor` / `discount_pct` | **fields absent** (pre-#88/#89 schema); `cover_image_url` is a raw storage key (CDN_BASE_URL unset); visual = manual | 🔴 FAIL (feature not deployed) |
| 5 | Auth gate | guest `GET /products…` · unauth `POST /cart/items` · unauth `GET /wallet/balance` | 200 · 401 · 401 | 200 · 401 `missing_token` · 401 `missing_token` | 🟢 PASS |

All four failures are **attributable to the stale build** (features merged 2026-06-04→06-06 vs build of 05-26), not to code defects. The 0085 shipping-zone matrix (istanbul→diyarbakir) could not be spot-checked: migration 0085 is not applied in prod (§7) and the endpoint doesn't emit ETA yet.

## 6. Metrics & logs

- **Metrics (point-in-time scrape of `core-svc:9100/metrics`):** zero 5xx since container start; `mopro_http_requests_total` shows only this audit's own probes — production has effectively **no organic traffic** (pre-launch). p95 dashboards: Grafana Cloud only (agent remote-writes; no on-host query API) → **manual-verify** for Salih; with ~0 traffic there is nothing meaningful to read yet.
- **App logs (7 d, `--tail 2000` per service):** core-svc, fin-svc, jobs-svc, redis, postgres-ecom, postgres-ledger — **0** panic/fatal/error lines.
- **Caddy:** 270 error lines, all one family — ACME renewal-info (ARI) refresh failing:
  `dial tcp: lookup acme-v02.api.letsencrypt.org on 127.0.0.11:53: server misbehaving` (+ a ZeroSSL "Issuer not found" variant). Cert is currently valid (§7) but the renewal path is intermittently broken from inside the container → F-DH-3.

## 7. Security, TLS, migrations

- **govulncheck:** latest runs all `success` (most recent 2026-06-06 on the branch merged as main head). No-new-vulns.
- **TLS:** `api.moproshop.com` serves Let's Encrypt (CN=api.moproshop.com, issuer E8), **valid to 2026-08-18** — 72 days runway, but see F-DH-3 (renewal errors).
- **Network posture:** DNS is direct-to-VDS; CloudFlare-only enforcement is still a Caddyfile TODO (pre-existing, CLAUDE.md §3.5 intent unmet) → F-DH-5.
- **Migrations (read-only `schema_migrations`):** ecom **62** (repo head 0085, −23) · ledger **77** (repo head 0080, −3); neither dirty. Drift is consistent with the stale deploy — repo-side migrations were never applied because the code that needs them never shipped. Per §3.5: reported, **not** auto-fixed.
- **STORAGE_*/CDN_BASE_URL:** absent from core-svc env (deploy-run STEP 7) — photo-upload gate still unprovisioned (known: project_photo_consumer_blocked).

## 8. Remediation actions — none taken

§3.6 triggers on a **down/unhealthy service**; there is none (12/12 up, healthz 200×3). The sole failure — deploy pipeline cannot ship images — requires script changes, image-ref/namespace fixes and registry credentials: all in §3.6's forbidden set (image redeploy, .env edits, multi-step recovery). Per protocol step 5: **STOP → ESCALATE** (Outcome C).

## 9. Open issues / follow-ups

| ID | Finding | Status | Size |
|---|---|---|---|
| F-DH-1 | Deploy pipeline cannot ship: wrong compose file (no `-f`, dev compose wins), host compose pins `ghcr.io/mopro/*` (stale + nonexistent namespace), no registry auth on host, no `set -e`/SHA assertion → green badge on no-op deploys | **ESCALATE** — blocker; separate prompt (deploy-pipeline repair: script `-f prod` + fail-fast + `ghcr.io/s4l1hs` refs + read-only PAT `docker login` + post-deploy `/__version` assertion) | M |
| F-DH-2 | Production 686 commits stale (built 2026-05-26); smoke targets 1–4 fail because parity features never shipped | **DEFER** — resolved automatically by first successful deploy after F-DH-1 | — |
| F-DH-3 | Caddy ACME ARI renewal errors (container DNS → ACME endpoints, 270 hits/7 d); cert hard-expires 2026-08-18 | **DEFER** — fix before ~2026-08-01; likely Docker DNS/upstream issue | S |
| F-DH-4 | Migration drift: ecom 62/0085, ledger 77/0080 | **DEFER** — apply via the proper deploy+migrate path with F-DH-1, never manually | — |
| F-DH-5 | CloudFlare-only enforcement not active; DNS direct-to-VDS; Caddyfile enforcer commented | **DEFER** — pre-existing launch-hardening TODO | S |
| F-DH-6 | deploy_script.sh mutates `/etc/mopro/.env` (root secrets file) and has now duplicated `IMAGE_NS=s4l1hs` twice (unprivileged existence-grep always misses) | **DEFER** — fold into F-DH-1 fix | XS |
| F-DH-7 | grafana-agent at 85 % of 300 M mem limit | **DEFER** — watch; raise only with INFRASTRUCTURE.md review | XS |
| F-DH-8 | Stale `EXPECTED_SHA_PREFIX=7b8d96cc` in deploy_script.sh (PR #49 era), printed but never asserted | **DEFER** — fold into F-DH-1 | XS |

## 10. Path-B readiness — NO-GO

**Blocking:** F-DH-1 (deploy pipeline), which alone gates F-DH-2/F-DH-4. Everything Path B would refine (filters, badges, bestseller, delivery-ETA, strikethrough) is merged but not running in production — auditing surfaces against a 12-day-old build would produce findings that are already fixed on main.

**Go-condition:** one successful deploy of `13aba07d`+ (images actually pulled, `/__version` = expected SHA, migrations 0085/0080 applied) + re-run of the 5-target smoke table above at 5/5. Infra is otherwise ready: containers, logs, resources, TLS and vuln posture are all green today.
