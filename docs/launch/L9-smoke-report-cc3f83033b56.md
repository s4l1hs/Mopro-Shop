# L9 Smoke Report

**LAUNCH_SHA:** `cc3f83033b56ec82201cbfe38c3ad0c0374e7d5c` (short: `cc3f83033b56`)  
**Timestamp (UTC):** `<fill in: date -u +%Y-%m-%dT%H:%M:%SZ>`  
**Tester:** Salih Sefer  
**Environment:** `api-staging.moproshop.com` / `staging.moproshop.com`  
**Verdict:** ☐ PASS  ☐ PASS WITH CAVEATS  ☐ FAIL

---

## Execution Checklist

> Complete each step in order. Do NOT skip to the next step if the current one has FAIL.

- [ ] DNS A record `api-staging.moproshop.com → 195.85.207.92` created and propagated
- [ ] `staging.moproshop.com → 195.85.207.92` DNS record created
- [ ] Part A — Pre-flight passed
- [ ] Part B — Deploy complete, SHA confirmed
- [ ] Part C — Seed counts pass (≥25 categories, ≥50 products)
- [ ] Part D — Backend smoke: FAIL count = 0
- [ ] Part E — k6 load test: all thresholds pass
- [ ] Part F — Grafana screenshots captured (4 dashboards × 2 timepoints = 8 screenshots)
- [ ] Part G — No critical alerts fired during load test
- [ ] Part H — Ledger reconcile: 0 unresolved alerts
- [ ] Part I — Manual UI handoff started

---

## BLOCKING PREREQUISITE

**DNS records not yet created.** Before running any step below, create these records:

```
api-staging.moproshop.com   A   195.85.207.92   TTL 300
staging.moproshop.com       A   195.85.207.92   TTL 300
```

Verify propagation:
```bash
dig +short api-staging.moproshop.com   # must return 195.85.207.92
curl -sf https://api-staging.moproshop.com/healthz  # must return HTTP 200
```

Also verify the staging Caddy block is serving. The block was added to
`deploy/caddy/Caddyfile` in commit `cc3f83033b56`. After DNS resolves, Caddy
will auto-provision a TLS certificate from Let's Encrypt. Wait 30–60s for cert.

---

## Part A — Pre-Flight Status

Run from the VDS (`ssh -p 4625 mopro@195.85.207.92`):

```bash
systemctl status mopro-core mopro-fin mopro-jobs caddy postgres redis
journalctl -u mopro-core --since "1 hour ago" --priority=err --no-pager | head -50
curl -sf https://api-staging.moproshop.com/healthz
curl -sf https://staging.moproshop.com/
curl -sf -H "Authorization: Bearer $GRAFANA_API_TOKEN" \
  "$GRAFANA_API_URL/api/dashboards/uid/mopro-slo-overview" | jq '.dashboard.title'
```

| Check | Status | Notes |
|-------|--------|-------|
| `systemctl status mopro-core` | ☐ OK / ☐ FAIL | |
| `systemctl status mopro-fin` | ☐ OK / ☐ FAIL | |
| `systemctl status mopro-jobs` | ☐ OK / ☐ FAIL | |
| `systemctl status caddy` | ☐ OK / ☐ FAIL | |
| `systemctl status postgres` (ecom) | ☐ OK / ☐ FAIL | |
| `systemctl status redis` | ☐ OK / ☐ FAIL | |
| `curl healthz` → 200 | ☐ OK / ☐ FAIL | |
| `curl staging.moproshop.com` → 200 | ☐ OK / ☐ FAIL | |
| `journalctl --priority=err` last hour | ☐ Clean / ☐ Errors: | |
| Grafana dashboard accessible | ☐ OK / ☐ FAIL | |

**journalctl output (if any errors):**
```
<paste here>
```

---

## Part B — Deploy

```bash
# From repo root on laptop
LAUNCH_SHA=$(git rev-parse main)
echo "LAUNCH_SHA: $LAUNCH_SHA"

# Build already verified locally — SHA cc3f83033b56 builds clean.
# For deploy we need Docker images:
make deploy-staging VERSION="$LAUNCH_SHA"

sleep 30

# Verify version
curl -s https://api-staging.moproshop.com/__version | jq
```

**Expected `/__version` response:**
```json
{
  "service": "core-svc",
  "sha": "cc3f83033b56",
  "version": "cc3f83033b56",
  "go_version": "go1.25",
  "built_at": "<timestamp>"
}
```

**Actual `/__version` response:**
```json
<paste here>
```

**SHA matches `cc3f83033b56`?** ☐ YES / ☐ NO → if NO, STOP.

---

## Part C — Seed

```bash
make seed-staging FORCE=1

curl -s https://api-staging.moproshop.com/categories | jq '.items | length'
curl -s 'https://api-staging.moproshop.com/products?limit=1&sort=newest' | jq '.total'
```

| Check | Expected | Actual | Pass? |
|-------|----------|--------|-------|
| `/categories` item count | ≥ 25 | | |
| `/products` total | ≥ 50 | | |

---

## Part D — Backend Smoke Results

```bash
BASE=https://api-staging.moproshop.com bash scripts/smoke/run.sh 2>&1 | tee /tmp/smoke-backend.log
tail -20 /tmp/smoke-backend.log
```

**Final totals from `/tmp/smoke-backend.log`:**
```
<paste the "═══ Smoke Results ═══" block here>
```

| Result | Count |
|--------|-------|
| PASS | |
| STUB (501 — not blocking) | |
| FAIL | |

**Failed checks (paste any ✗ lines):**
```
<paste here, or "none">
```

> FAIL count > 0 → STOP. STUBs are acceptable.

---

## Part E — Load Test Results

```bash
k6 run --env BASE=https://api-staging.moproshop.com scripts/loadtest/k6-smoke.js \
  2>&1 | tee /tmp/k6-smoke.log
```

**k6 threshold results:**

| Threshold | Passed? | Measured Value |
|-----------|---------|---------------|
| `http_req_duration{type:browse} p(95) < 500ms` | ☐ PASS / ☐ FAIL | `ms` |
| `http_req_duration{type:browse} p(99) < 2000ms` | ☐ PASS / ☐ FAIL | `ms` |
| `http_req_failed rate < 1%` | ☐ PASS / ☐ FAIL | `%` |
| `auth_error_rate < 5%` | ☐ PASS / ☐ FAIL | `%` |

**k6 end-of-run summary (paste from `/tmp/k6-smoke.log`):**
```
<paste k6 table + custom summary block here>
```

---

## Part F — Grafana Dashboard Screenshots

Place screenshot files under `docs/launch/assets/L9-cc3f83033b56/`.

Naming convention:
- `slo-overview-baseline.png` — before k6 starts
- `slo-overview-mid.png` — at ~5 min (50 VU sustained)
- `slo-overview-burst.png` — at burst (100 VU)
- `slo-overview-post.png` — after k6 finishes
- Same pattern for `financial-health-*`, `infra-health-*`, `backup-cron-*`

| Dashboard | Baseline | Mid-Test | Burst | Post-Test |
|-----------|----------|----------|-------|-----------|
| SLO Overview | ![](assets/L9-cc3f83033b56/slo-overview-baseline.png) | ![](assets/L9-cc3f83033b56/slo-overview-mid.png) | ![](assets/L9-cc3f83033b56/slo-overview-burst.png) | ![](assets/L9-cc3f83033b56/slo-overview-post.png) |
| Financial Health | | | | |
| Infra Health | | | | |
| Backup & Cron | | | | |

**Observations:**
- Error rate during test: `%`
- DB pool peak utilization: `%`
- Redis memory peak: `MB`
- Outbox lag peak: `s`
- Anomalies: `none / describe`

---

## Part G — Alerts That Fired During Load Test

```bash
# Check Grafana Alerting → Alert rules → "Firing" tab during and after the test
```

| Alert Name | Severity | Fired At | Cleared At | Root Cause | Blocking? |
|------------|----------|----------|------------|------------|-----------|
| | | | | | |

> **Zero critical alerts = pass.** Warning alerts: note for tuning, not blocking.

---

## Part H — Ledger Reconciliation Post-Load

```bash
# On VDS:
docker exec fin-svc /fin-svc --run-once --cron=ledger-reconcile-weekly 2>&1 | tee /tmp/reconcile.log

# Check for unresolved drift
psql "$LEDGER_DATABASE_URL" \
  -c "SELECT check_name, currency_or_period, drift_minor, created_at
      FROM wallet_schema.ledger_alerts
      WHERE resolved_at IS NULL
      ORDER BY created_at DESC
      LIMIT 20;"
```

**Reconcile log (last 10 lines):**
```
<paste /tmp/reconcile.log tail here>
```

**`ledger_alerts` query output:**
```
<paste psql output here — must be "0 rows" for PASS>
```

**Reconciliation verdict:** ☐ BALANCED (0 rows) ← PASS  
**OR** ☐ IMBALANCED ← **BLOCKING — see docs/runbooks/ledger-imbalanced.md**

---

## Part I — Manual UI Checklist Status

**Handoff doc:** `scripts/smoke/manual-handoff.md`

| Status | ☐ Completed  ☐ In progress  ☐ Not started yet |
|--------|----------------------------------------------|

> The backend smoke + load test can pass without the UI checklist, but L9 final verdict
> requires at minimum Sections 8 (Checkout) and 11 (Integration Checks) completed.

---

## Acceptance Criteria Summary

| Criterion | Met? | Notes |
|-----------|------|-------|
| DNS records created and resolving | ☐ YES / ☐ NO | **Blocking — do first** |
| All backend smoke checks pass (FAIL=0, STUBs OK) | ☐ YES / ☐ NO | |
| k6 SLO thresholds met | ☐ YES / ☐ NO | |
| Zero critical alerts during load test | ☐ YES / ☐ NO | |
| Ledger reconciliation: 0 unresolved alerts | ☐ YES / ☐ NO | |
| This smoke report committed to repo | ☐ YES / ☐ NO | |
| Manual UI checklist Sections 8+11 complete | ☐ YES / ☐ NO | |

---

## Final Verdict

**☐ PASS** — All criteria met.

**☐ PASS WITH CAVEATS:**
```
1.
2.
```

**☐ FAIL:**
```
1.
2.
```

---

## Step 10 — Commit Command

Once all sections are filled:

```bash
LAUNCH_SHA=cc3f83033b56ec82201cbfe38c3ad0c0374e7d5c

git add docs/launch/L9-smoke-report-cc3f83033b56.md \
        docs/launch/assets/L9-cc3f83033b56/

git commit -m "$(cat <<'EOF'
docs(launch): L9 smoke report — verdict <PASS|PASS-CAVEATS|FAIL>

SHA: cc3f83033b56
Smoke: X passed, Y stub, Z failed
k6: p95=Xms, err=Y%
Reconcile: balanced / N unresolved alerts

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
