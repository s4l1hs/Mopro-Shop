# L10 — Production Cutover Plan

**Status:** DRAFT — awaiting L9c sign-off  
**Owner:** @salih  
**Estimated execution time:** 3–4 hours (with 30-min DNS propagation buffer)

**Gate:** L9c sign-off (`docs/launch/L9c-manual-residual.md`) is a hard prerequisite.  
**Smoke report:** `docs/launch/L9-smoke-report-4e73f254617c.md` — confirmed PASS.  
**E2E coverage:** `web/e2e/` — all automated tests passing on staging.

---

## Pre-Cutover Gate (T-24h)

All of these must be green before scheduling the cutover window.

| # | Gate | Owner | Status |
|---|------|-------|--------|
| G1 | L9c sign-off: all sections PASS or PASS WITH CAVEATS | @salih | ☐ |
| G2 | `pnpm test:e2e --reporter=list` — all tests passing on staging | CI | ☐ |
| G3 | `go test -race ./...` — all Go tests passing on main branch | CI | ☐ |
| G4 | `golangci-lint run` — no blocking linter errors | CI | ☐ |
| G5 | Backblaze B2 backup: `restic snapshots` shows snapshot from last 24h | @salih | ☐ |
| G6 | Sipay production credentials in hand (merchant ID, API key, webhook secret) | @salih | ☐ |
| G7 | CloudFlare production zone configured with correct DNS records (see §4) | @salih | ☐ |
| G8 | Production VDS provisioned and SSH accessible | @salih | ☐ |
| G9 | On-call plan defined for launch day — who to page for payment failures | @salih | ☐ |

> **@salih TODO:** Confirm G6 (Sipay production credentials) and G9 (on-call roster) before scheduling.

---

## 1. Secret Rotation (T-2h before cutover window)

Rotate all staging secrets; generate fresh production secrets. Never reuse staging credentials in production.

```bash
# On production VDS — generate new secrets
openssl rand -hex 32  # JWT_SECRET
openssl rand -hex 32  # SESSION_SECRET
openssl rand -hex 32  # POSTGRES_ECOM_PASSWORD
openssl rand -hex 32  # POSTGRES_LEDGER_PASSWORD
openssl rand -hex 32  # REDIS_PASSWORD
openssl rand -hex 32  # PGBOUNCER_AUTH_SECRET
openssl rand -hex 32  # RESTIC_PASSWORD
```

Write secrets to `/opt/mopro/.env` (chmod 600, root-only). Template:

```env
# ── Identity ─────────────────────────────────────────────────────
JWT_SECRET=<generated>
SESSION_SECRET=<generated>
JWT_EXPIRY=15m
REFRESH_EXPIRY=30d

# ── Database ─────────────────────────────────────────────────────
POSTGRES_ECOM_HOST=postgres-ecom
POSTGRES_ECOM_PORT=5432
POSTGRES_ECOM_DB=ecom
POSTGRES_ECOM_USER=ecom_app
POSTGRES_ECOM_PASSWORD=<generated>
POSTGRES_LEDGER_HOST=postgres-ledger
POSTGRES_LEDGER_PORT=5432
POSTGRES_LEDGER_DB=ledger
POSTGRES_LEDGER_USER=ledger_app
POSTGRES_LEDGER_PASSWORD=<generated>

# ── Redis ─────────────────────────────────────────────────────────
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/0
REDIS_PASSWORD=<generated>

# ── PSP ──────────────────────────────────────────────────────────
PSP_PROVIDER=sipay
SIPAY_MERCHANT_ID=<production value>        # @salih: fill from Sipay merchant portal
SIPAY_API_KEY=<production value>            # @salih: fill from Sipay merchant portal
SIPAY_WEBHOOK_SECRET=<production value>     # @salih: fill from Sipay merchant portal
SIPAY_BASE_URL=https://provisioning.sipay.com.tr/ccpayment

# ── Observability ─────────────────────────────────────────────────
GRAFANA_CLOUD_API_KEY=<production value>    # @salih: from Grafana Cloud dashboard
SLACK_DLQ_WEBHOOK_URL=<production value>   # @salih: create dedicated #mopro-dlq channel

# ── Backup ────────────────────────────────────────────────────────
RESTIC_REPOSITORY=s3:s3.us-east-005.backblazeb2.com/<bucket-name>
RESTIC_PASSWORD=<generated>
B2_ACCOUNT_ID=<production value>            # @salih: Backblaze B2 production bucket
B2_ACCOUNT_KEY=<production value>

# ── App ───────────────────────────────────────────────────────────
ENV=production
MARKET=TR
LOG_LEVEL=info
DEV_OTP_ACCEPT_ANY=false                   # CRITICAL: must be false in production
```

> **CRITICAL:** `DEV_OTP_ACCEPT_ANY=false` — any-code OTP bypass must be disabled in production.

---

## 2. Database Initialization (T-1.5h)

Run migrations on a clean production database. Do NOT copy staging data to production.

```bash
# SSH into production VDS
ssh -p <port> root@<prod-vds-ip>

cd /opt/mopro

# Pull production image
docker compose pull

# Run migrations — ecom DB first
docker compose run --rm migrate-tool \
  --db ecom \
  --url "postgres://ecom_app:${POSTGRES_ECOM_PASSWORD}@postgres-ecom:5432/ecom?sslmode=require"

# Then ledger DB
docker compose run --rm migrate-tool \
  --db ledger \
  --url "postgres://ledger_app:${POSTGRES_LEDGER_PASSWORD}@postgres-ledger:5432/ledger?sslmode=require"

# Seed reference data (categories, currencies, commission rules, business calendars)
docker compose run --rm core-svc seed --market=TR
```

Verify migrations:

```bash
docker compose run --rm migrate-tool --db ecom status
docker compose run --rm migrate-tool --db ledger status
```

Both should show all migrations as "applied".

> **@salih TODO:** Confirm production DB host/port and whether you're using managed Postgres or self-hosted. Adjust connection strings above accordingly.

---

## 3. Pre-Traffic Smoke (T-1h)

Start the stack, run internal healthchecks before cutting DNS.

```bash
# Start all services
docker compose up -d

# Wait for all containers healthy
docker compose ps --format "table {{.Name}}\t{{.Status}}"
# Expected: all show "healthy" or "running"

# Internal healthcheck (using VDS-local URLs)
curl -sf http://localhost:8080/healthz | jq .   # core-svc
curl -sf http://localhost:8081/healthz | jq .   # fin-svc
curl -sf http://localhost:8082/healthz | jq .   # jobs-svc
curl -sf http://localhost:8080/__version | jq . # confirm correct SHA

# Verify Caddy is routing correctly
curl -sf https://moproshop.com/healthz          # via Caddy (requires DNS or /etc/hosts)
curl -sf https://moproshop.com/__version        # confirm buildinfo SHA

# Run k6 smoke against production (browse-only — no checkout with real Sipay)
k6 run --env BASE=https://api.moproshop.com \
  scripts/loadtest/k6-smoke.js
```

> **@salih TODO:** Confirm production domain names (`moproshop.com` vs `moproshop.com.tr`) and Caddy config.

---

## 4. DNS Cutover Sequence (T-0)

**Order matters:** Cut API subdomain first, then web. This way the backend is ready before web traffic arrives.

```
Step 4.1 — CloudFlare: Point api.moproshop.com → production VDS IP
           TTL: 60s (set 24h before to ensure low TTL is propagated)
           Proxy: ON (CloudFlare proxied — enables WAF + rate limiting)

Step 4.2 — Wait 5 minutes for propagation. Verify:
           curl -H "Host: api.moproshop.com" https://<prod-vds-ip>/healthz

Step 4.3 — CloudFlare: Point moproshop.com (apex) → production VDS IP
           Proxy: ON

Step 4.4 — CloudFlare: Point www.moproshop.com → CNAME moproshop.com
           Proxy: ON

Step 4.5 — Wait 5 minutes. Verify web:
           curl -I https://moproshop.com/
           # Expected: 200 or 307 redirect

Step 4.6 — CloudFlare: Set full SSL/TLS mode to "Full (Strict)"
           (Caddy will handle the certificate — verify via Caddy logs)
```

> **@salih TODO:** Confirm exact CloudFlare zone name and whether you want the `.com.tr` ccTLD in addition to `.com` for Turkish market trust.

Rollback (DNS): Re-point CloudFlare DNS back to staging VDS IP (195.85.207.92) at any step.

---

## 5. Sipay Production Cutover

After DNS is live and web is accessible:

```bash
# 1. Update PSP_PROVIDER env to production on VDS
# Edit /opt/mopro/.env — already done in §1 above if SIPAY_BASE_URL is production

# 2. Register production webhook URL in Sipay merchant portal:
#    POST callback: https://api.moproshop.com/webhooks/sipay
#    (Sipay sends POST to this URL after payment capture/failure)

# 3. Verify webhook secret matches SIPAY_WEBHOOK_SECRET in .env

# 4. Run a test transaction with Sipay production sandbox (if available)
#    — or perform a minimal real-money test (₺1) with your own card
#    — immediately refund via Sipay merchant portal

# 5. Confirm core-svc receives webhook:
docker compose logs core-svc --tail=20 | grep webhook
```

> **@salih TODO:** Log into Sipay merchant portal and register the production webhook URL before cutover. Confirm whether Sipay provides a production sandbox mode or requires real transactions for integration testing.

---

## 6. Day-0 Monitoring (First 2 hours post-cutover)

Monitor these dashboards continuously for the first 2 hours:

| Signal | Where | Alert threshold |
|--------|-------|-----------------|
| Error rate | Grafana Cloud — `http_req_failed` | > 0.5% → investigate |
| p95 latency | Grafana Cloud — `http_req_duration p(95)` | > 500ms browse → investigate |
| Payment failures | `docker compose logs core-svc \| grep "payment.*fail"` | Any → immediate |
| Webhook receipts | `docker compose logs core-svc \| grep sipay` | Missing after order → check |
| DB connections | `docker compose stats postgres-ecom postgres-ledger` | > 80% pool → scale pgbouncer |
| Redis memory | `docker compose exec redis redis-cli INFO memory` | > 600MB → investigate |
| Container restart | `docker compose ps` | Any restart → check logs |

**Grafana Agent** is pre-configured to push metrics to Grafana Cloud.

> **@salih TODO:** Set up Grafana Cloud alerts with PagerDuty/Slack integration before cutover. The Slack DLQ channel (`SLACK_DLQ_WEBHOOK_URL`) should be monitored on launch day.

---

## 7. Launch Announcement Order

Execute in this exact sequence to avoid announcing before the system is ready:

1. Internal team Slack notification: "Production is live — internal testing window open (15 min)"
2. Internal team spot-check: 2 people complete a real ₺1 test purchase independently
3. If both succeed → proceed to public announcement
4. **Public announcement channels** (execute simultaneously):
   - Instagram post
   - Twitter/X post  
   - WhatsApp business broadcast
   - Email to early-access list
5. Monitor error rate for 30 minutes after announcement

> **@salih TODO:** Prepare social media copy and email draft in advance. Confirm early-access list export format.

---

## 8. Rollback Plan

### Rollback trigger conditions (any one of these → immediate rollback)

- Payment error rate > 5% for more than 5 minutes
- Any 5xx error on `/checkout/initiate` or `/webhooks/sipay`
- Database corruption or failed migration
- Security incident (unexpected data exposure, auth bypass)

### Rollback procedure (< 15 minutes)

```bash
# Step R1: Redirect DNS back to staging (immediate — CloudFlare propagates in < 60s)
# CloudFlare Dashboard → api.moproshop.com → change IP back to 195.85.207.92
# CloudFlare Dashboard → moproshop.com → change IP back to 195.85.207.92

# Step R2: Stop production services
ssh root@<prod-vds-ip> "cd /opt/mopro && docker compose down"

# Step R3: Post-mortem Slack notification to team
# "Production rollback triggered — investigating. ETA for root cause: 1 hour."

# Step R4: Preserve production logs before any restart
docker compose logs > /tmp/prod-incident-$(date +%Y%m%d-%H%M%S).log
```

### Post-rollback
- Analyze logs from Step R4
- File GitHub issue with `incident` label
- Fix root cause on staging, re-run L9c checklist
- Schedule new cutover window

---

## 9. Post-Cutover Audit (T+24h)

Run these checks the day after launch to confirm clean state:

```bash
# 1. Verify ledger integrity (double-entry invariant)
docker compose exec fin-svc /app/fin-svc reconcile --date=$(date +%Y-%m-%d)

# 2. Confirm cashback engine is processing (if any orders delivered)
docker compose exec fin-svc /app/fin-svc cashback status

# 3. Verify seller payout cron ran at 02:30 UTC
docker compose logs fin-svc | grep "seller-payout-daily"

# 4. Check backup ran
docker compose logs restic-backup | grep "snapshot"
restic snapshots | head -5

# 5. Review error logs for any silent failures
docker compose logs core-svc | grep -E "ERROR|CRITICAL" | tail -50
docker compose logs fin-svc  | grep -E "ERROR|CRITICAL" | tail -50

# 6. Check OTP rate-limit keys didn't spike (Redis)
docker compose exec redis redis-cli KEYS "rl:otp*" | wc -l
```

---

## 10. Sign-Off Matrix

| Phase | Responsible | Verified by | Timestamp |
|-------|-------------|-------------|-----------|
| Pre-cutover gates (§0) | @salih | @salih | |
| Secret rotation (§1) | @salih | @salih | |
| DB migrations (§2) | @salih | @salih | |
| Pre-traffic smoke (§3) | @salih | @salih | |
| DNS cutover (§4) | @salih | @salih | |
| Sipay production (§5) | @salih | @salih | |
| Day-0 monitoring (§6) | @salih | — | |
| Public announcement (§7) | @salih | — | |
| Post-cutover audit (§9) | @salih | @salih | T+24h |

---

## Open TODOs requiring @salih input

| # | Item | Needed by |
|---|------|-----------|
| T1 | Production VDS IP address | Pre-cutover gate |
| T2 | Production domain name(s): `moproshop.com` only, or also `.com.tr`? | DNS cutover §4 |
| T3 | Sipay production credentials (merchant ID, API key, webhook secret) | §1 Secret rotation |
| T4 | On-call roster for launch day — who handles payment failures after hours? | §0 Gate G9 |
| T5 | Backblaze B2 production bucket name | §1 |
| T6 | Grafana Cloud API key for production workspace | §1 |
| T7 | Slack `#mopro-dlq` channel webhook URL for DLQ alerts | §1 |
| T8 | CloudFlare zone name and SSL certificate strategy | §4 |
| T9 | Early-access email list for announcement | §7 |
| T10 | Is a real ₺1 test purchase acceptable for production Sipay validation, or does Sipay provide a production sandbox? | §5 |
