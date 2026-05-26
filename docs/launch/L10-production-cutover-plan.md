# L10 — Mopro Shop Production Cutover Runbook

**Audience**: Salih Sefer, solo operator.
**Goal**: Execute the cutover from staging to live production with zero unrecoverable data loss, minimum downtime, and clear rollback at every step.

This runbook is structured as nine sequential phases plus three appendices. Do not skip a phase. Each phase has a sign-off line at the end — initial and timestamp before proceeding.

---

## Phase 0 — Pre-cutover Gate

Every line must be ✅ before scheduling the cutover window.

### Engineering (all complete)
- [ ] L1 — Flutter QA checklist exists at `docs/ops/flutter-qa-l1.md`
- [ ] L2 — Catalog seed script + data ready
- [ ] L3a/b/c — Sipay backend + web + Flutter integration committed
- [ ] L4a/b — Grafana wiring + dashboards + alerts committed (config-as-code)
- [ ] L5 — Backup pipeline operational (B2 backend, restic, systemd timers)
- [ ] L9 — Backend smoke pass PASS verdict committed at `docs/launch/L9-smoke-report-*.md`
- [ ] L9b — k6 load test all thresholds green
- [ ] L9c-auto — Playwright suite green
- [ ] L9c-manual-residual — completed by Salih, no critical bugs filed

### External (waiting / in flight)
- [ ] L6 — LTD incorporation complete + Turkish tax registration number issued
- [ ] L7 — Turkish bank account active, IBAN saved to ops vault
- [ ] L3 prod — Sipay production merchant agreement signed, production credentials issued (gated by L6 + L7)
- [ ] Legal review — Mesafeli Satış Sözleşmesi, KVKK Aydınlatma Metni, Ön Bilgilendirme Formu signed off

### Domain & DNS (already done in this session)
- [x] moproshop.com migrated to Cloudflare (gray-cloud on all subdomains)
- [x] Caddy serving HTTPS on api.moproshop.com, api-staging.moproshop.com, etc.

**Phase 0 sign-off**: ____________ Date: __________

---

## Phase 1 — Account & Service Provisioning

You don't have Grafana Cloud or Slack accounts yet. Set them up before any other phase. ~45 min total.

### 1A — Backblaze B2 (verify existing setup, 5 min)

B2 bucket and credentials already exist. Just verify.

1. Log in to https://secure.backblaze.com/b2_buckets.htm
2. Confirm bucket `mopro-backups-prod` exists. Note its bucket ID.
3. Navigate to Application Keys (`https://secure.backblaze.com/app_keys.htm`)
4. Confirm an active application key exists with read+write on `mopro-backups-prod`
5. Verify keyID and applicationKey in `/etc/mopro/.env` match the active key:
```bash
   ssh -p 4625 mopro@195.85.207.92
   sudo grep -E '^B2_(KEY_ID|APP_KEY|BUCKET)=' /etc/mopro/.env
```
6. Test backup pipeline end-to-end:
```bash
   sudo systemctl start mopro-backup.service
   journalctl -u mopro-backup.service -n 80 --no-pager | tail -30
   # Expect: "Saved new snapshot..." line + final exit 0
   sudo -u mopro-backup restic -r "b2:mopro-backups-prod:mopro-backups" snapshots
   # Expect: ≥ 1 snapshot listed
```

✅ when restic lists at least one snapshot. Do NOT proceed with later phases until this works.

### 1B — Grafana Cloud (from scratch, 15 min)

1. Go to https://grafana.com/auth/sign-up/create-user
2. Sign up with `sefersalih017@gmail.com`. Verify email.
3. Create organization name: `Mopro Shop`. Region: `EU (Frankfurt)` for lowest latency from your Hetzner VDS.
4. Select **Free tier** (10k active metrics series, 50GB logs/month, 50GB traces/month — sufficient for first 6 months).
5. After org creation, the Grafana Cloud portal shows three stack endpoints:
   - **Prometheus (Mimir)** — note the URL like `https://prometheus-prod-XX-prod-eu-XXX.grafana.net/api/prom/push` and the User ID (numeric)
   - **Loki** — URL like `https://logs-prod-XXX.grafana.net/loki/api/v1/push` and Loki User ID
   - **Tempo** — URL like `https://tempo-prod-XX-prod-eu-XXX.grafana.net:443` and Tempo User ID
6. Generate **service account + API token**:
   - Navigate to your stack: Administration → Users and access → Service Accounts
   - Click "Add service account"
   - Display name: `mopro-prod-deploy`
   - Role: **Editor** (needed for dashboard + alert provisioning)
   - Click "Create token", name it `mopro-prod-deploy-token`, set expiration to 1 year
   - Copy the token immediately — Grafana shows it once only
7. Also create a **single push token** that covers Prometheus + Loki + Tempo:
   - In the same stack, Connections → Add new connection → "Hosted Prometheus metrics"
   - Generate a "Cloud Access Policy" token with scopes: `metrics:write`, `logs:write`, `traces:write`
   - Save this token — you'll inject it into your remote_write configs
8. Save all values to a local secrets file (NOT committed):
   - GRAFANA_API_TOKEN=<service account token from step 6>
   - GRAFANA_PROM_USER=<numeric Prom user ID>
   - GRAFANA_PROM_PASS=<push token from step 7>
   - GRAFANA_PROM_URL=<full /api/prom/push URL>
   - GRAFANA_LOKI_USER=<numeric Loki user ID>
   - GRAFANA_LOKI_PASS=<push token from step 7>
   - GRAFANA_LOKI_URL=<full /loki/api/v1/push URL>
   - GRAFANA_TEMPO_USER=<numeric Tempo user ID>
   - GRAFANA_TEMPO_PASS=<push token from step 7>
   - GRAFANA_TEMPO_URL=<full Tempo URL>
### 1C — Slack workspace (from scratch, 15 min)

1. Go to https://slack.com/get-started → "Create a new workspace"
2. Sign up with `sefersalih017@gmail.com`, name the workspace `Mopro Shop` or `mopro-ops`
3. Skip team invitations (you're solo for now). You can invite later.
4. Create four channels (Channels → Add channels → Create new):
   - `#mopro-alerts` — warning-severity alerts
   - `#mopro-panic` — critical-severity alerts (use this as a phone notification channel — enable mobile notifications "All new messages")
   - `#mopro-info` — info-severity events, deploy notifications
   - `#mopro-dlq` — dead letter queue growth + worker failures
5. Generate Incoming Webhook URLs (one per channel):
   - Apps → "Add apps" → search "Incoming Webhooks" → "Add to Slack"
   - For each channel: click "Add to a new workspace", select target channel, click "Allow"
   - Slack displays a webhook URL. Copy each.
6. Save webhook URLs to your local secrets file:
   - SLACK_WEBHOOK=<#mopro-alerts URL>
   - SLACK_PANIC_WEBHOOK=<#mopro-panic URL>
   - SLACK_INFO_WEBHOOK=<#mopro-info URL>
   - SLACK_DLQ_WEBHOOK_URL=<#mopro-dlq URL>
7. On your phone, install the Slack app, log in to the workspace, and configure `#mopro-panic` with custom notifications: "All new messages" + enable critical override on iOS / "Override Do Not Disturb" on Android. This is your overnight wake-up channel.

### 1D — Healthchecks.io (verify existing, 5 min)

UUIDs already in `.env`. Verify each check is configured correctly at https://healthchecks.io/checks/.

For each of the 6 checks, confirm:
- Schedule matches actual cron timing (e.g. daily 03:00 for backup)
- Grace period is reasonable (1h for daily jobs, 30 min for hourly)
- Notification integrations include Slack webhook → `#mopro-panic`

**Phase 1 sign-off**: ____________ Date: __________

---

## Phase 2 — Load & Stress Testing

Run this against the staging stack (`api-staging.moproshop.com`) to validate the same VDS can handle production load. Solo operator means no one will save you from a Sunday-night traffic spike — find your breaking point in advance.

### 2A — Establish baseline (10 min)

```bash
# On VDS
docker stats --no-stream
# Note: CPU%, MEM USAGE / LIMIT for each container — this is your idle baseline

# DB pool size baseline
docker exec postgres-ecom psql -U mopro -d mopro_ecom -c "SHOW max_connections;"
# Expect: 100 (default) or whatever you configured
```

### 2B — Run three load tiers

Three k6 scripts: `scripts/loadtest/k6-1k.js`, `k6-10k.js`, `k6-100k.js`. Each defines a "unique users per hour" rate using `constant-arrival-rate` executor.

If these scripts don't exist yet, generate them from the existing `k6-smoke.js` template — only the `scenarios` block changes:

#### `k6-1k.js` — 1,000 unique users/hour (≈ 0.28 new users/sec, 8 req/sec aggregate)
```javascript
scenarios: {
  unique_users: {
    executor: 'constant-arrival-rate',
    rate: 1000,
    timeUnit: '1h',
    duration: '15m',
    preAllocatedVUs: 50,
    maxVUs: 200,
  },
},
thresholds: {
  'http_req_duration': ['p(95)<500'],
  'http_req_failed': ['rate<0.01'],
},
```

#### `k6-10k.js` — 10,000 unique users/hour (≈ 2.8/sec, 83 req/sec aggregate)
```javascript
scenarios: {
  unique_users: {
    executor: 'constant-arrival-rate',
    rate: 10000,
    timeUnit: '1h',
    duration: '15m',
    preAllocatedVUs: 200,
    maxVUs: 1000,
  },
},
thresholds: {
  'http_req_duration': ['p(95)<800'],
  'http_req_failed': ['rate<0.02'],
},
```

#### `k6-100k.js` — 100,000 unique users/hour (≈ 28/sec, 833 req/sec aggregate)
```javascript
scenarios: {
  unique_users: {
    executor: 'constant-arrival-rate',
    rate: 100000,
    timeUnit: '1h',
    duration: '10m',
    preAllocatedVUs: 1000,
    maxVUs: 3000,
  },
},
thresholds: {
  'http_req_duration': ['p(95)<2000'],
  'http_req_failed': ['rate<0.05'],
},
```

### 2C — Run sequence (1.5 hours total)

Execute each tier from your laptop. Between tiers, give the VDS 5 min to settle.

```bash
# Tier 1 (15 min run)
k6 run --env BASE=https://api-staging.moproshop.com scripts/loadtest/k6-1k.js 2>&1 | tee /tmp/k6-1k.log
sleep 300

# Tier 2 (15 min run)
k6 run --env BASE=https://api-staging.moproshop.com scripts/loadtest/k6-10k.js 2>&1 | tee /tmp/k6-10k.log
sleep 300

# Tier 3 (10 min run, the hard one)
k6 run --env BASE=https://api-staging.moproshop.com scripts/loadtest/k6-100k.js 2>&1 | tee /tmp/k6-100k.log
```

### 2D — Monitor during each tier

In a separate terminal SSH'd to the VDS, run `htop` and `docker stats` continuously. Watch:

**Caddy** (reverse proxy limits)
- Connection count: `docker exec caddy curl -s http://localhost:2019/metrics 2>/dev/null | grep caddy_http_requests_in_flight`
- Caddy default max connections: unlimited at the Caddy layer. Watch for OS-level limits.
- Check OS file descriptor limit: `cat /proc/$(docker inspect caddy --format '{{.State.Pid}}')/limits | grep "open files"` — should be ≥ 1048576

**Containers** (CPU + RAM allocation)
- During 100k tier, no container should sit at 100% CPU for > 10 seconds sustained
- Memory: if any container approaches its limit, it will OOM-kill — add `mem_limit` in docker-compose.yml if missing
- Recommendation:
  - core-svc: cpus=2, mem_limit=2g
  - fin-svc: cpus=2, mem_limit=2g
  - jobs-svc: cpus=1, mem_limit=1g
  - caddy: cpus=1, mem_limit=512m
  - postgres-*: cpus=2, mem_limit=2g each
  - redis: cpus=1, mem_limit=1g
  - meilisearch: cpus=1, mem_limit=1g

**PostgreSQL connection pool**
```bash
# During load, run this from another SSH session:
watch -n 2 'docker exec postgres-ecom psql -U mopro -d mopro_ecom -c "SELECT count(*) FROM pg_stat_activity WHERE datname='\''mopro_ecom'\'';"'
```
If you approach `max_connections` (default 100), you're at risk. Options:
1. Increase max_connections to 200 in postgresql.conf and restart
2. Tune pgbouncer pool sizes (default pool_mode=transaction is best for high concurrency)
3. Reduce app-side connection pool sizes if they're set too high

### 2E — Document the breaking point

Whichever tier first crosses a threshold, that's your production ceiling. Record it in this runbook:

| Tier | p95 | err rate | Bottleneck observed | Pass? |
|------|-----|----------|---------------------|-------|
| 1k/hr | __ms | __% | | ✅ / ❌ |
| 10k/hr | __ms | __% | | ✅ / ❌ |
| 100k/hr | __ms | __% | | ✅ / ❌ |

If tier 100k fails:
- Acceptable to launch if tier 10k passes — you won't see 100k traffic in week 1
- Document the constraint in `docs/ops/capacity-plan.md`
- Add an alert that fires at 70% of your proven ceiling
- Plan VDS upgrade or horizontal scaling before traffic ever approaches the ceiling

### 2F — Tune the rate limiter

Caddyfile uses `rate_limit` (commented out per TODO). Now's the time to enable:

Add to the `(api_routes)` snippet in `/opt/mopro/deploy/caddy/Caddyfile`:

```caddy
rate_limit {
    zone api_per_ip {
        key     {client_ip}
        window  1m
        max     600         # 10 req/sec per IP, generous for SPA
    }
    zone otp_per_ip {
        key     {client_ip}
        match {
            path /auth/otp/*
        }
        window  10m
        max     5           # OTP abuse protection
    }
}
```

Requires `caddy-ratelimit` plugin — rebuild Caddy image with `xcaddy build --with github.com/mholt/caddy-ratelimit`. Or use `caddy-l4` if you've already got that.

Restart Caddy:
```bash
docker compose -p mopro-prod restart caddy
```

Re-run tier 100k to confirm rate limiter doesn't false-positive on legitimate traffic.

**Phase 2 sign-off**: ____________ Date: __________ Breaking point tier: __________

---

## Phase 3 — Production Environment Setup (mopro-prod compose project)

Production runs on the same VDS as staging but is fully isolated via a separate Docker Compose project. Both projects share the host network but have independent databases, volumes, and env files.

### 3A — Create production compose file

```bash
ssh -p 4625 mopro@195.85.207.92
cd /opt/mopro/deploy
cp docker-compose.prod.yml docker-compose.prod.yml.pre-cutover.bak

# Edit docker-compose.prod.yml — ensure these are set:
# - project name: mopro-prod
# - container names suffixed with -prod (e.g. postgres-ecom-prod)
# - volume names suffixed with -prod (e.g. pg-ecom-prod, restic-cache-prod)
# - env_file: /opt/mopro/.env.prod
# - port bindings DO NOT conflict with staging's (use different host ports, all on 127.0.0.1)
```

Container port mapping (host:container, all bound to 127.0.0.1 — Caddy is the only public-facing service):
- core-svc-prod: 127.0.0.1:18080:8080
- fin-svc-prod: 127.0.0.1:18081:8081
- jobs-svc-prod: 127.0.0.1:18082:8080
- postgres-ecom-prod: 127.0.0.1:15432:5432
- postgres-ledger-prod: 127.0.0.1:15433:5432
- postgres-config-prod: 127.0.0.1:15434:5432
- redis-prod: 127.0.0.1:16379:6379
- meilisearch-prod: 127.0.0.1:17700:7700

Caddy is shared (one Caddy instance handles both stagings + production via different vhosts). Production vhosts already exist in Caddyfile (api.moproshop.com, etc.).

### 3B — Create independent volumes

```bash
docker volume create mopro-prod_pg-ecom-prod
docker volume create mopro-prod_pg-ledger-prod
docker volume create mopro-prod_pg-config-prod
docker volume create mopro-prod_redis-prod
docker volume create mopro-prod_meili-prod
docker volume create mopro-prod_restic-cache-prod
```

### 3C — Create .env.prod (the production secrets file)

```bash
sudo cp /etc/mopro/.env /etc/mopro/.env.prod
sudo chown root:mopro /etc/mopro/.env.prod
sudo chmod 640 /etc/mopro/.env.prod
sudo ln -sf /etc/mopro/.env.prod /opt/mopro/.env.prod
```

Now edit `.env.prod` to rotate all secrets to production-grade values. See Phase 4 below.

### 3D — Do NOT start the production stack yet

Production containers stay stopped until Phase 5 (DB init) is complete. Verify:
```bash
docker compose -p mopro-prod -f docker-compose.prod.yml --env-file /opt/mopro/.env.prod config | head -50
# Verify config parses correctly; no errors
```

**Phase 3 sign-off**: ____________ Date: __________

---

## Phase 4 — Production Secret Rotation

Every value in `.env.prod` that came from staging defaults must be regenerated for production. Solo operator means you're the only one who knows these secrets — store them in a password manager (1Password, Bitwarden) with a Mopro Shop vault.

### 4A — Generate fresh secrets

For each of the following, generate cryptographically strong values:

```bash
# Database passwords (one per service, 20 of them)
for svc in ECOM LEDGER IDENTITY CATALOG CART ORDER PAYMENT SELLER SEARCH \
           WALLET COMMISSION TREASURY CASHBACK SELLERPAYOUT NOTIFICATION \
           SUPPORT MEDIA SIZEFINDER ANTIFRAUD EINVOICE; do
  printf '%s_DB_PASSWORD=%s\n' "$svc" "$(openssl rand -base64 32 | tr -d '+/=' | head -c 32)"
done

# Redis password
echo "REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '+/=' | head -c 32)"

# JWT signing key (64 bytes hex)
echo "JWT_SIGNING_KEY=$(openssl rand -hex 64)"

# PII pepper (32 bytes hex)
echo "PII_PEPPER=$(openssl rand -hex 32)"

# Admin internal token
echo "ADMIN_INTERNAL_TOKEN=$(openssl rand -base64 32 | tr -d '+/=' | head -c 48)"

# Meilisearch master key
echo "MEILI_MASTER_KEY=$(openssl rand -base64 32 | tr -d '+/=' | head -c 32)"
```

Paste output into your password manager. Then edit `/etc/mopro/.env.prod` and replace each corresponding line.

### 4B — Inject Grafana + Slack credentials from Phase 1

Replace these in `.env.prod` with the values you saved in Phase 1B and 1C:
- GRAFANA_PROM_USER=...
- GRAFANA_PROM_PASS=...
- GRAFANA_LOKI_USER=...
- GRAFANA_LOKI_PASS=...
- GRAFANA_TEMPO_USER=...
- GRAFANA_TEMPO_PASS=...
- GRAFANA_API_TOKEN=...
- SLACK_WEBHOOK=...
- SLACK_PANIC_WEBHOOK=...
- SLACK_INFO_WEBHOOK=...
- SLACK_DLQ_WEBHOOK_URL=...

These get swapped to production values in Phase 6.

### 4E — Critical: DEV_OTP_ACCEPT_ANY must be false

```bash
grep -E '^DEV_OTP_ACCEPT_ANY' /etc/mopro/.env.prod
# Expected: not present, OR present and explicitly set to false
# If present and true, IMMEDIATELY change to false. This bypasses SMS verification.
sudo sed -i 's/^DEV_OTP_ACCEPT_ANY=.*/DEV_OTP_ACCEPT_ANY=false/' /etc/mopro/.env.prod
```

### 4F — Verify .env.prod permissions

```bash
ls -l /etc/mopro/.env.prod
# Expected: -rw-r----- 1 root mopro

stat -c '%a' /etc/mopro/.env.prod
# Expected: 640
```

**Phase 4 sign-off**: ____________ Date: __________

---

## Phase 5 — Database Initialization

Apply migrations to the empty production databases, then seed initial catalog data.

### 5A — Start only the database containers

```bash
docker compose -p mopro-prod -f docker-compose.prod.yml --env-file /opt/mopro/.env.prod \
  up -d postgres-ecom-prod postgres-ledger-prod postgres-config-prod redis-prod

sleep 10
docker compose -p mopro-prod ps
# All three pg + redis should be healthy
```

### 5B — Apply migrations in order

```bash
cd /opt/mopro
make migrate-prod
# This should apply ALL outstanding migrations to all 20+ databases
# Critical: migrations 0061 + 0062 (added during L9) MUST apply
```

Verify migration state per DB:
```bash
docker exec postgres-ecom-prod psql -U ecom_admin -d mopro_ecom -c "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 5;"
docker exec postgres-ledger-prod psql -U ledger_admin -d mopro_ledger -c "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 5;"
```

### 5C — Run production seed

```bash
make seed-prod
# Will prompt: "Type SEED PROD to confirm:" → type exactly "SEED PROD"
```

Verify seed:
```bash
docker exec postgres-ecom-prod psql -U ecom_admin -d mopro_ecom -c "SELECT count(*) FROM categories;"   # ≥ 25
docker exec postgres-ecom-prod psql -U ecom_admin -d mopro_ecom -c "SELECT count(*) FROM brands;"       # ≥ 30
docker exec postgres-ecom-prod psql -U ecom_admin -d mopro_ecom -c "SELECT count(*) FROM products WHERE is_active = true;"  # ≥ 50
```

### 5D — Start application services

```bash
docker compose -p mopro-prod -f docker-compose.prod.yml --env-file /opt/mopro/.env.prod \
  up -d core-svc-prod fin-svc-prod jobs-svc-prod meilisearch-prod

sleep 30
docker compose -p mopro-prod ps
# All services healthy
```

### 5E — Pre-DNS smoke test (Host header trick)

Production hostnames aren't pointing at the production stack yet (DNS still routes to staging). Test via Host header override:

```bash
# Health checks
curl -k -H "Host: api.moproshop.com" https://195.85.207.92/healthz
curl -k -H "Host: moproshop.com" https://195.85.207.92/

# Catalog
curl -k -H "Host: api.moproshop.com" https://195.85.207.92/categories | jq '.items | length'   # ≥ 25
curl -k -H "Host: api.moproshop.com" https://195.85.207.92/products?limit=12 | jq '.items | length'   # 12
```

Then run the full backend smoke script with Host header override:
```bash
BASE=https://195.85.207.92 \
CURL_EXTRA_ARGS="-k -H 'Host: api.moproshop.com'" \
bash scripts/smoke/run.sh 2>&1 | tee /tmp/prod-smoke-pre-dns.log
```

Expect: same pass/stub/fail counts as L9 smoke against staging. Any new failures → STOP, investigate. Do NOT proceed to DNS cutover until production smoke passes.

**Phase 5 sign-off**: ____________ Date: __________

---

## Phase 6 — Sipay Production Plumbing Test (sandbox creds first)

Before flipping DNS, validate that the production codebase + production environment can complete a Sipay sandbox transaction end-to-end. This catches deployment-specific bugs before any real money is involved.

### 6A — Sipay sandbox plumbing test (no real money)

`.env.prod` still has sandbox Sipay credentials from Phase 4. Run a full sandbox transaction against the production stack:

```bash
# From your laptop, with Host header override
BASE_URL=https://195.85.207.92
HOST_HEADER="Host: api.moproshop.com"

# 1. Login with the staging test phone (works because OTP bypass... wait, this is prod, no bypass)
# Use your own real phone number. Production has no OTP bypass.
curl -k -H "$HOST_HEADER" -X POST $BASE_URL/auth/otp/request \
  -H 'Content-Type: application/json' \
  -d '{"phone":"+90<your real number>"}'
# Wait for actual SMS, then verify
```

This is awkward — production already requires real OTP. Two options:
- **Option A (recommended)**: just do the real ₺1 test (Phase 7) directly. Sandbox plumbing test serves limited value once you can already smoke endpoints with curl + Host header.
- **Option B**: temporarily enable `DEV_OTP_ACCEPT_ANY=true` for 30 minutes during this test, then immediately set back to false. **Risky** — write a calendar alarm for "REVERT DEV_OTP" at +30min before you start.

Choose A.

### 6B — Switch to Sipay production credentials (when they arrive)

When your Sipay merchant agreement clears and production credentials are issued:

```bash
sudo nano /etc/mopro/.env.prod
# Replace:
#   SIPAY_BASE_URL=https://app.sipay.com.tr/ccpayment   (production)
#   SIPAY_APP_ID=<prod app id>
#   SIPAY_APP_SECRET=<prod app secret>
#   SIPAY_MERCHANT_ID=<prod merchant id>
#   SIPAY_MERCHANT_KEY=<prod merchant key>
#   PSP_WEBHOOK_SECRET=<prod webhook secret>
```

Restart fin-svc + core-svc to pick up new env:
```bash
docker compose -p mopro-prod -f docker-compose.prod.yml --env-file /opt/mopro/.env.prod \
  restart core-svc-prod fin-svc-prod
```

Register the production webhook URL with Sipay:
https://api.moproshop.com/payments/webhook/sipay

(Sipay merchant dashboard → Webhook Settings → set URL + save the webhook secret to .env.prod)

**Phase 6 sign-off**: ____________ Date: __________ Sipay prod creds active: Y / N

---

## Phase 7 — DNS Cutover

Currently both staging and production hostnames resolve to 195.85.207.92, but only staging vhosts are served by Caddy. Production vhosts are served too — they just don't get traffic because nobody is hitting `api.moproshop.com` yet.

Actually that's not quite right. Let me re-check what's deployed.

Production hostnames in Caddy serve from container `core-svc:8080` etc. — which currently maps to the staging stack (the original containers). After Phase 5, the production containers are running but on different host ports (18080 etc.). So we need to update Caddy upstreams.

### 7A — Update Caddy upstreams for production vhosts

```bash
ssh -p 4625 mopro@195.85.207.92
sudo nano /opt/mopro/deploy/caddy/Caddyfile

# In production vhost blocks (api.moproshop.com, moproshop.com, seller, admin, fin):
# Change reverse_proxy targets:
#   reverse_proxy core-svc:8080  →  reverse_proxy core-svc-prod:8080
#   reverse_proxy fin-svc:8081   →  reverse_proxy fin-svc-prod:8081
#   reverse_proxy jobs-svc:8080  →  reverse_proxy jobs-svc-prod:8080

# Staging vhost blocks stay unchanged (still target staging containers)
```

Validate and reload Caddy:
```bash
docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker restart caddy   # NOT docker exec caddy caddy reload — we learned reload-via-admin-API doesn't work reliably
```

### 7B — Smoke against the production stack via real hostnames

```bash
# From your laptop (no Host header trick needed — Caddy now routes to prod containers)
curl -sI https://api.moproshop.com/healthz
curl -sI https://moproshop.com/
curl -s https://api.moproshop.com/categories | jq '.items | length'
```

Expected: same counts as staging.

### 7C — Cloudflare proxy enable (web traffic only)

Up to now all DNS records are gray-cloud. Now flip the web hostnames to orange-cloud for DDoS + CDN protection:

In Cloudflare dashboard → DNS records:
- `@` (moproshop.com) → flip Proxy status to **Proxied** (orange)
- `www` → flip to **Proxied** (orange)
- `seller` → flip to **Proxied** (orange)
- `admin` → flip to **Proxied** (orange)
- `fin` → flip to **Proxied** (orange)
- `api` → **leave gray** (DNS only) — Sipay webhooks need direct origin
- `api-staging` → leave gray
- `staging` → leave gray

Verify:
```bash
# Orange-cloud hostname should return CF-Ray header
curl -sI https://moproshop.com/ | grep -i cf-ray
# Expected: cf-ray: <id>

# Gray-cloud hostname should NOT have CF-Ray header
curl -sI https://api.moproshop.com/healthz | grep -i cf-ray
# Expected: no output
```

### 7D — Cloudflare hardening

In Cloudflare dashboard, set:
- **SSL/TLS Mode**: Full (strict)
- **Always Use HTTPS**: ON
- **Minimum TLS Version**: 1.2
- **Automatic HTTPS Rewrites**: ON
- **Bot Fight Mode**: ON (Security → Bots)
- **Security Level**: Medium
- **Browser Integrity Check**: ON

### 7E — Optional but recommended: lock down VDS firewall to Cloudflare IPs

```bash
# Add UFW rules: only allow :80 + :443 from Cloudflare IP ranges on orange-cloud hosts
# Keep :443 open universally for api.moproshop.com (gray-cloud)
# Keep :4625 (SSH) restricted to your home/office IP

# Fetch CF IPs
curl -s https://www.cloudflare.com/ips-v4 > /tmp/cf-v4.txt
curl -s https://www.cloudflare.com/ips-v6 > /tmp/cf-v6.txt

# Defer this lock-down to day +3 — wait 72h after cutover to confirm CF routing stable
# before locking down. Use docs/ops/firewall-lockdown.md for the procedure.
```

**Phase 7 sign-off**: ____________ Date: __________

---

## Phase 8 — Real ₺1 Test Transaction

Now do the real-money smoke. ₺1 of your own money, refunded within 5 minutes, validates the full payment plumbing under live conditions. This catches bugs that sandbox can't (real bank 3DS flow, real settlement timing).

### 8A — Make the test purchase

1. On your phone or laptop browser, open https://moproshop.com
2. Find a product, add to cart (or create a test product priced at ₺1 in advance via admin panel — recommended)
3. Proceed to checkout
4. Use your real address + real phone (you'll get a real SMS OTP)
5. At Sipay 3DS page, enter your **real personal credit card**
6. Complete 3DS challenge with bank SMS code
7. After redirect to /orders/[id]?status=success, verify:
```bash
   ssh -p 4625 mopro@195.85.207.92
   docker exec postgres-ecom-prod psql -U ecom_admin -d mopro_ecom -c \
     "SELECT id, status, total_minor, created_at FROM orders ORDER BY created_at DESC LIMIT 1;"

   docker exec postgres-ledger-prod psql -U ledger_admin -d mopro_ledger -c \
     "SELECT order_id, status, monthly_amount_minor, total_months FROM cashback_plans ORDER BY created_at DESC LIMIT 1;"
```
   Expected: order row exists, status=`captured`, cashback plan created with non-zero monthly amount.

### 8B — Immediately refund

```bash
# Via admin panel (assuming you have one wired up)
curl -X POST https://api.moproshop.com/v1/admin/refunds \
  -H "Authorization: Bearer $ADMIN_INTERNAL_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"order_id":"<id from 8A>","reason":"launch_smoke_test"}'
```

Verify refund:
```bash
docker exec postgres-ledger-prod psql -U ledger_admin -d mopro_ledger -c \
  "SELECT * FROM refunds ORDER BY created_at DESC LIMIT 1;"
```

### 8C — Settlement check (day +1)

The ₺1 will appear in Sipay's daily settlement report on day +1. Log in to Sipay merchant dashboard, verify the ₺1 settled and the refund cancelled it. Should net ₺0 in your bank account after 1-3 business days.

**Phase 8 sign-off**: ____________ Date: __________ ₺1 captured + refunded: Y / N

---

## Phase 9 — Soft Launch (20 Beta Users)

Don't open to the public on day 0. Invite 20 trusted users for a 48-72h closed beta. Catches bugs you wouldn't catch as the developer.

### 9A — Compile beta tester list

Recommended: 5 family members + 10 friends + 5 close associates / mentors. Avoid press/influencers — too risky for week 1.

### 9B — Send invitation email

Send each tester the template in Appendix A (below). Stagger over 24h so you can respond to early bugs without 20 simultaneous reports.

### 9C — Monitor closely

For the 48-72h beta window:
- Keep Grafana SLO Overview pinned in browser
- Check `#mopro-alerts` every 30 minutes during waking hours
- Reply to bug reports within 2 hours during waking hours
- Track every beta tester order: did it capture? Did cashback plan get created?

### 9D — Public launch criteria

Open to public ONLY when ALL of these are true after 48h beta:
- [ ] At least 10 beta orders successfully captured
- [ ] Zero critical bugs unfixed
- [ ] Ledger reconciliation balanced on day 0 + day 1
- [ ] No webhook delivery failures
- [ ] No PagerDuty pages for critical alerts
- [ ] Cashback payouts process correctly (wait for the daily cron run)

**Phase 9 sign-off**: ____________ Date: __________ Public launch authorized: Y / N

---

## Day-0 Solo Operator Monitoring

You have no backup. Plan accordingly.

### Active hours (09:00 - 23:00 Istanbul)

- Refresh Grafana SLO Overview every 30 min
- Check Slack channels (#mopro-alerts, #mopro-panic, #mopro-dlq) on every refresh
- Have phone with Slack notifications ON
- Don't go more than 2h without checking systems

### Sleep hours (23:00 - 09:00 Istanbul)

- Slack #mopro-panic configured to override Do Not Disturb on your phone
- Anything in #mopro-panic = wake up and respond
- #mopro-alerts can wait until morning (less severe)
- Set 6am alarm to do a "did everything survive the night" check before normal day

### Critical thresholds (warrant immediate intervention)

- Any 5xx rate > 1% sustained for 5 minutes
- DB connection pool > 95%
- Any `ledger_imbalanced` alert (zero tolerance)
- Disk usage > 92%
- Sipay webhook delivery failing > 10% rate
- Backup not completed by 04:00

### Auto-recovery already in place

- Caddy auto-restart on container crash (Docker restart policy)
- All app containers same
- Postgres replication N/A (single instance — be aware single point of failure)
- Redis BGSAVE every hour (`/var/lib/mopro/snapshots`)
- Restic backup nightly to B2

---

## Rollback Plan

### Trigger 1: Before DNS cutover (Phase 7 not yet executed)
- No public traffic landed
- Production stack is running but only accessible via Host header trick
- Action: just stop the production stack:
```bash
  docker compose -p mopro-prod -f docker-compose.prod.yml down
```
- Staging is unaffected. Investigate, fix, restart from Phase 5.

### Trigger 2: After DNS cutover, before any orders (Phase 7-8 in progress)
- Public hostnames resolve to production stack
- No real customer money has changed hands yet
- Action: flip Caddy back to staging upstreams:
```bash
  ssh -p 4625 mopro@195.85.207.92
  sudo cp /opt/mopro/deploy/caddy/Caddyfile.pre-cutover.bak /opt/mopro/deploy/caddy/Caddyfile
  docker restart caddy
```
- Production stack stays up but receives no traffic. Investigate, fix, redo Phase 7.

### Trigger 3: After real orders captured (Phase 8 complete, beta running)
- **DO NOT roll back databases** — real money + orders are in the production DB
- Hotfix the bug: SSH in, edit code in the running container is unsafe; redeploy binaries with fix
- If unfixable in < 30 min, enable maintenance mode:
```bash
  # Caddy override: return 503 to all /api/* requests with JSON body
  # Save to /opt/mopro/deploy/caddy/Caddyfile.maintenance and atomically swap
  docker restart caddy
```
- Comms: update social channels + email beta testers about brief maintenance window
- Once fix is live, lift maintenance mode

### Trigger 4: Ledger imbalance detected
- Critical. Don't roll back — investigate.
- Stop new orders from being placed: enable maintenance mode on /checkout/* and /payments/* routes
- Run ledger reconciler manually, examine which journal is imbalanced
- Fix the root cause (probably a posting bug)
- Manually post a correcting entry if needed (document the correction in `docs/ops/ledger-corrections.md`)
- Resume orders only after reconciler confirms balance

---

## Post-Cutover Audit (day +1, day +7)

### Day +1

Run automatically + manually verify:
- [ ] Backup ran successfully overnight (`restic snapshots` shows fresh snapshot)
- [ ] All 6 Healthchecks pings landed on schedule
- [ ] No `#mopro-panic` alerts overnight
- [ ] End-of-day ledger reconciliation balanced
- [ ] Sample 10 random orders from day 0, verify each has:
  - payment_intent.status = `captured`
  - cashback_plan exists with correct monthly amount
  - outbox events emitted (check `outbox_events` table)
- [ ] Sipay settlement report shows expected ₺ amounts

### Day +7

- [ ] One full week of green metrics
- [ ] No data loss incidents
- [ ] No customer-facing payment failures
- [ ] Disk usage growth predictable (extrapolate to next 90 days, plan capacity)
- [ ] Decide: lock down VDS firewall to Cloudflare IPs (Phase 7E)

---

## Sign-off Matrix

| Phase | Sign-off | Date | Notes |
|-------|----------|------|-------|
| 0 — Pre-cutover gate | ☐ | | |
| 1 — Account provisioning | ☐ | | |
| 2 — Load testing | ☐ | | Breaking point: ___ |
| 3 — Prod environment setup | ☐ | | |
| 4 — Secret rotation | ☐ | | |
| 5 — DB initialization | ☐ | | |
| 6 — Sipay plumbing test | ☐ | | Prod creds: Y / N |
| 7 — DNS cutover | ☐ | | |
| 8 — ₺1 real test | ☐ | | |
| 9 — Soft launch | ☐ | | Beta count: ___ |
| Public launch authorized | ☐ | | |

---

## Appendix A — Soft Launch Invitation Email Template

Subject line: **Mopro Shop'a özel davet — aldıkça sürekli kazan**
Merhaba [İSİM],
Mopro Shop'u kuruyoruz: alışveriş yaptıkça aylık cashback kazanmaya devam ettiğin yeni nesil bir
Türk pazaryeri. Aldığın her ürün için, fiyatın belli bir yüzdesini her ay düzenli olarak
hesabına yatırıyoruz — bir kere değil, ürünün cashback planı boyunca her ay.
Genel kullanıma açmadan önce 20 kişilik kapalı bir test grubu başlatıyoruz ve seni içeride
görmek istiyorum.
Senden istediğim:

https://moproshop.com adresinden hesap aç
En az bir ürün satın al (gerçek kart, gerçek ücret — küçük bir şey de olabilir)
Karşılaştığın her sorunu, garip gelen her şeyi bana bildir
Cashback'in geldiğini ay sonunda doğrula

Karşılığında:

İlk ayın cashback'i Mopro tarafından %50 artırılır
Lansman sonrasında "kurucu üye" rozeti
Doğrudan benim WhatsApp numaram, soruların için: [WHATSAPP]

Beta süresi: 48-72 saat
Lansman tarihi: Beta'da kritik bir sorun çıkmazsa hafta içinde
Sorun yaşarsan veya bir şey kafanı kurcalarsa, lütfen kibar olmana gerek yok — kötü
geribildirim çok daha değerli.
Teşekkürler,
Salih
moproshop.com
PS: Linki paylaşma henüz. Public lansmana kadar 20 kişiyle sınırlı tutuyoruz.
---

## Appendix B — Load Test Script Locations

- `scripts/loadtest/k6-smoke.js` — existing smoke test (used in L9)
- `scripts/loadtest/k6-1k.js` — 1k unique users/hour tier (create from template)
- `scripts/loadtest/k6-10k.js` — 10k unique users/hour tier
- `scripts/loadtest/k6-100k.js` — 100k unique users/hour tier

If the tier scripts don't exist, generate them following the templates in Phase 2B above.

---

## Appendix C — Emergency Contacts

| Service | Dashboard URL | Login |
|---------|---------------|-------|
| Hetzner VDS | https://console.hetzner.cloud | sefersalih017@gmail.com |
| Cloudflare | https://dash.cloudflare.com | sefersalih017@gmail.com |
| Backblaze B2 | https://secure.backblaze.com | sefersalih017@gmail.com |
| Grafana Cloud | https://grafana.com/orgs/moproshop | sefersalih017@gmail.com |
| Slack workspace | https://moproshop.slack.com | sefersalih017@gmail.com |
| Sipay merchant | https://merchant.sipay.com.tr | (TBD when contract active) |
| GitHub repo | https://github.com/[org]/Mopro-Shop | sefersalih017@gmail.com |
| Healthchecks.io | https://healthchecks.io | sefersalih017@gmail.com |

---

**End of L10 Production Cutover Runbook.**

Execute phases sequentially. Do not skip sign-offs. Do not proceed past a phase with unresolved blockers.
