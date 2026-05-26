# L9 Smoke Report

**LAUNCH_SHA:** `<fill in: git rev-parse --short=12 main>`  
**Timestamp (UTC):** `<fill in: date -u +%Y-%m-%dT%H:%M:%SZ>`  
**Tester:** `<fill in>`  
**Environment:** `api-staging.moproshop.com` / `staging.moproshop.com`  
**Verdict:** ☐ PASS  ☐ PASS WITH CAVEATS  ☐ FAIL

---

## Part A — Pre-Flight Status

| Check | Status | Notes |
|-------|--------|-------|
| `systemctl status mopro-core` | ☐ OK / ☐ FAIL | |
| `systemctl status mopro-fin` | ☐ OK / ☐ FAIL | |
| `systemctl status mopro-jobs` | ☐ OK / ☐ FAIL | |
| `systemctl status caddy` | ☐ OK / ☐ FAIL | |
| `systemctl status postgres` (ecom) | ☐ OK / ☐ FAIL | |
| `systemctl status redis` | ☐ OK / ☐ FAIL | |
| `curl -sf https://api-staging.moproshop.com/healthz` | ☐ 200 / ☐ FAIL | |
| `curl -sf https://staging.moproshop.com/` | ☐ 200 / ☐ FAIL | |
| Grafana `mopro-slo-overview` dashboard accessible | ☐ OK / ☐ FAIL | |
| `journalctl --priority=err` last hour: no errors | ☐ Clean / ☐ Errors found | |

> If any pre-flight check fails: **STOP. Fix and restart from Part A.**

---

## Part B — Deploy

**SHA deployed:** `<fill in>`  
**Deploy timestamp:** `<fill in>`  
**`curl /__version` response:**
```json
<paste output here>
```

**Deployment result:** ☐ SUCCESS  ☐ FAILED (see notes below)

---

## Part C — Seed

| Check | Result | Notes |
|-------|--------|-------|
| `GET /categories | .items | length` | `<value>` (must be ≥ 25) | |
| `GET /products?limit=1 | .total` | `<value>` (must be ≥ 50) | |
| Seed command used | `make seed-staging FORCE=1` | |

---

## Part D — Backend Smoke Results

**Run command:**
```bash
BASE=https://api-staging.moproshop.com bash scripts/smoke/run.sh | tee /tmp/smoke-backend.log
```

**Final line from `/tmp/smoke-backend.log`:**
```
<paste the "=== Smoke Results: X passed, Y failed ===" line>
```

**Full log attached:** `/tmp/smoke-backend.log`

| Result | Count |
|--------|-------|
| PASS | |
| STUB (known 501 — not blocking) | |
| FAIL | |

**Failed checks (if any):**
```
<paste any ✗ lines here>
```

> If FAIL count > 0: **STOP. Fix and redo from Part B.**

---

## Part E — Load Test Results

**Run command:**
```bash
k6 run --env BASE=https://api-staging.moproshop.com scripts/loadtest/k6-smoke.js | tee /tmp/k6-smoke.log
```

**k6 threshold results:**

| Threshold | Passed? | Measured Value |
|-----------|---------|---------------|
| `http_req_duration{type:browse} p(95) < 500ms` | ☐ PASS / ☐ FAIL | `<value>ms` |
| `http_req_duration{type:browse} p(99) < 2000ms` | ☐ PASS / ☐ FAIL | `<value>ms` |
| `http_req_failed rate < 1%` | ☐ PASS / ☐ FAIL | `<value>%` |
| `auth_error_rate < 5%` | ☐ PASS / ☐ FAIL | `<value>%` |

**k6 summary table:** (paste from `/tmp/k6-smoke.log`)
```
<paste k6 end-of-run table here>
```

> If any threshold FAIL: investigate Grafana dashboards. Warning thresholds = not blocking. Critical alerts during test = blocking.

---

## Part F — Grafana Dashboard Screenshots (taken DURING load test)

Attach screenshots taken mid-test (during the 100-VU burst window) and post-test.

| Dashboard | Mid-Test Screenshot | Post-Test Screenshot |
|-----------|--------------------|--------------------|
| SLO Overview (`mopro-slo-overview`) | `<attach>` | `<attach>` |
| Financial Health (`mopro-financial`) | `<attach>` | `<attach>` |
| Infra Health (`mopro-infra`) | `<attach>` | `<attach>` |
| Backup & Cron Health (`mopro-backup-cron`) | `<attach>` | `<attach>` |

**Observations from dashboards:**
- Error rate during test: `<value>%`
- DB pool peak utilization: `<value>%`
- Redis memory peak: `<value> MB`
- Any anomalies: `<none / describe>`

---

## Part G — Alerts That Fired During Test

| Alert Name | Severity | Fired At | Cleared At | Root Cause | Blocking? |
|------------|----------|----------|------------|------------|-----------|
| | | | | | |

> Critical alerts = blocking. Warning alerts = note for post-L9 tuning, not blocking.

---

## Part H — Ledger Reconciliation Post-Load

**Command run:**
```bash
# On the VDS:
docker exec fin-svc /fin-svc --run-once --cron=ledger-reconcile-weekly 2>&1
```

**Reconcile output (last log lines):**
```
<paste here>
```

**Check for unresolved ledger drift:**
```sql
SELECT check_name, currency_or_period, drift_minor, created_at
FROM wallet_schema.ledger_alerts
WHERE resolved_at IS NULL
ORDER BY created_at DESC
LIMIT 20;
```

**Query result:**
```
<paste here — must be 0 rows for PASS>
```

**Reconciliation verdict:** ☐ BALANCED (0 unresolved alerts)  ☐ IMBALANCED ← **BLOCKING**

> Any unresolved alerts = **STOP. Do not proceed.** See `docs/runbooks/ledger-imbalanced.md`.

---

## Part I — Manual UI Checklist Status

**Handoff doc:** `scripts/smoke/manual-handoff.md`  
**Tester:** `<fill in>`  
**Completed:** ☐ Yes  ☐ No (partial — list remaining sections below)

| Section | Status | Blocking Issues |
|---------|--------|-----------------|
| 1. Cold Load + Theme | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |
| 2. Auth | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |
| 3. Home Page | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |
| 4. Catalog | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |
| 5. PDP | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |
| 6. Search | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |
| 7. Cart | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |
| 8. Checkout | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |
| 9. Order Confirmation | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |
| 10. Account | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |
| 11. Integration Checks | ☐ PASS / ☐ CAVEATS / ☐ FAIL / ☐ SKIPPED | |

**Known stubs / acceptable gaps for L9:**
```
<list here>
```

---

## Acceptance Criteria Summary

| Criterion | Met? | Notes |
|-----------|------|-------|
| All 25+ backend smoke checks pass (or STUB) | ☐ YES / ☐ NO | |
| k6 load test hits SLO thresholds | ☐ YES / ☐ NO | |
| Zero critical alerts during load test | ☐ YES / ☐ NO | |
| Ledger reconciliation balanced (0 unresolved alerts) | ☐ YES / ☐ NO | |
| This smoke report committed to repo | ☐ YES / ☐ NO | |
| Manual UI handoff doc completed | ☐ YES / ☐ NO | |

---

## Final Verdict

**☐ PASS** — All acceptance criteria met. Stack is ready for production cutover.

**☐ PASS WITH CAVEATS** — Issues found but judged non-blocking for launch:
```
1. <issue> — <go/no-go judgment>
2. <issue> — <go/no-go judgment>
```

**☐ FAIL** — Blocking issues found. Must be fixed and L9 re-run before launch:
```
1. <issue> — <severity>
2. <issue> — <severity>
```

---

## Post-L9 Actions (regardless of verdict)

- [ ] Fix any warning-severity items found during smoke
- [ ] Add any new smoke check gaps to `scripts/smoke/run.sh` for next run
- [ ] Review k6 p95 trend — if > 300ms steady, investigate before cutover
- [ ] Set up production monitoring alerts in PagerDuty before cutover
- [ ] Confirm backup cron ran and `mopro_backup_last_success_timestamp_seconds` is fresh
- [ ] Confirm Healthchecks.io shows all 6 checks green
- [ ] Commit this report: `git add docs/launch/L9-smoke-report-<SHA>.md && git commit`
