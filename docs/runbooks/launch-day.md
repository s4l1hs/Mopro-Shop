# Launch-Day Runbook — Mopro Shop

> **Audience:** Whoever is on-call the day the platform is opened to real users.
> **Purpose:** Step-by-step guide for interpreting the readiness matrix, executing the launch sequence, and rolling back if something goes wrong.

---

## 1. Pre-Launch Checklist (T-24h)

Run the readiness script and verify all FP criteria (FAIL = no-go, WARN = review):

```bash
cd /path/to/mopro-shop
./deploy/scripts/launch-readiness.sh --json
```

Expected output for a clean launch state:

```
PASS  A   containers-running             12 running (≥12)
PASS  A   disk-usage                     42% used (< 70%)
PASS  A   postgres-version               version_num=160014 (≥160000 = 16.x)
PASS  A   redis-pong                     PONG received
PASS  A   port-443-open                  localhost:443 reachable
PASS  A   port-80-open                   localhost:80 reachable (redirect)

PASS  B   env-file-exists                /opt/mopro/.env present
PASS  B   jwt-key-length                 43 chars (≥32)
PASS  B   pii-kek-length                 44 chars (≥32)
PASS  B   pii-pepper-length              43 chars (≥32)
PASS  B   restic-pass-length             44 chars (≥16)
PASS  B   no-change-me                   0 CHANGE_ME placeholders
PASS  B   tls-cert-expiry                85 days remaining (≥30)
PASS  B   caddyfile-finsvc-port          fin-svc:8081 confirmed in Caddyfile

PASS  C   platform-accounts              10 platform accounts (≥5)
PASS  C   cashback-k-constant            CashbackK=156000 in calculator.go
PASS  C   trigger-ledger-balance         ledger_balance_check trigger present
PASS  C   trigger-plan-immutable         cashback_plan_immutable_trg present
PASS  C   commission-rules-tr            42 TR commission rules
PASS  C   business-calendars-tr          69 TR business-day calendar entries (≥50)

PASS  D   healthz-core-svc               core-svc/healthz → 200
PASS  D   healthz-fin-svc                fin-svc/healthz → 200
PASS  D   healthz-jobs-svc               jobs-svc/healthz → 200
PASS  D   metrics-core-svc               core-svc:9100/metrics reachable
PASS  D   metrics-fin-svc                fin-svc:9101/metrics reachable
PASS  D   metrics-jobs-svc               jobs-svc:9102/metrics reachable
WARN  D   grafana-creds                  GRAFANA_PROM_USER/PASS empty — no remote metrics dashboard
WARN  D   healthchecks-uuids             HC cashback=empty payout=empty — cron failures will be silent

PASS  E   baseline-report-exists         baseline-2026-05-24T...md — 2h old (≤7 days)
PASS  E   baseline-slos-pass             All latency SLOs ✅ in baseline report
WARN  E   baseline-error-rate            Error-rate/check-pass ❌ in baseline — expected deferral
PASS  E   no-5xx-1h                      0 5xx responses in last 1h

WARN  F   products-seeded                0 products — buyers will see empty catalog at launch
WARN  F   sellers-onboarded              0 sellers — no orders can be fulfilled at launch
PASS  F   categories-count               42 categories in ref_schema.categories

WARN  G   backup-timer-active            mopro-backup.timer status='not-found' — run install-backup.sh
WARN  G   backup-healthcheck-uuid        HEALTHCHECK_BACKUP_UUID empty
WARN  G   restore-healthcheck-uuid       HEALTHCHECK_RESTORE_UUID empty

PASS  H   disk-watch-timer               disk-watch.timer is active
PASS  H   runbooks-exist                 All 5 runbooks present
PASS  H   dlq-empty                      0 open DLQ entries
PASS  H   outbox-lag-ecom                0 unpublished outbox entries (ecom)
PASS  H   outbox-lag-ledger              0 unpublished outbox entries (ledger)
WARN  H   manual-go-nogo                 Operator must review this report and give explicit go/no-go
```

**Hard blockers (FAIL = no-go):** Any check in sections A–D, F (categories), H (disk-watch, DLQ, outbox).

**Known acceptable WARNs at launch:**
| Check | Reason deferred |
|---|---|
| `grafana-creds` | Optional cloud dashboards; local Grafana still works |
| `healthchecks-uuids` | Configure after launch week |
| `baseline-error-rate` | S7/S8 fail by design until real products/sellers exist |
| `products-seeded` | First seller onboards at launch |
| `sellers-onboarded` | First seller onboards at launch |
| `backup-timer-active` | Install before end of launch day |
| `backup-healthcheck-uuid` | Set after backup runs once successfully |
| `restore-healthcheck-uuid` | Set after first restore drill |

---

## 2. T-1h: Final Checks

```bash
# Run section-by-section for final confirmation
./deploy/scripts/launch-readiness.sh --section A
./deploy/scripts/launch-readiness.sh --section B
./deploy/scripts/launch-readiness.sh --section C
./deploy/scripts/launch-readiness.sh --section H

# Confirm latest smoke test is green
cd load-tests && ./run.sh smoke
```

---

## 3. Launch Sequence

### Step 1 — Remove any traffic blocks

If CloudFlare has a maintenance page or firewall rule blocking new users, remove it now.

```bash
# Verify API is reachable from external IP
curl -I https://api.moproshop.com/healthz
```

### Step 2 — Enable new user registration

Confirm `REGISTRATION_ENABLED=true` in `/opt/mopro/.env` on VDS, or remove the feature flag:

```bash
ssh -p 4625 mopro@195.85.207.92 \
  "grep REGISTRATION_ENABLED /opt/mopro/.env"
```

### Step 3 — Verify first-order flow manually

Using the Mopro mobile app (or curl), complete a real end-to-end order:
1. Register as a new buyer → receive OTP → confirm phone
2. Browse categories → find a product → add to cart
3. Place order → confirm payment via Sipay test card
4. Check that `order.status = 'paid'` in the DB
5. Confirm `cashback_schema.plans` has a pending plan row (if within 3 BD window)

### Step 4 — Monitor for 30 minutes

Keep the following tabs open:
- `ssh -p 4625 mopro@195.85.207.92 'sudo docker stats'` — container resource usage
- Caddy access log: `sudo docker logs -f caddy`
- Redis Streams lag: `sudo docker exec redis redis-cli -a $REDIS_PASSWORD XLEN ecom.order.delivered.v1`

---

## 4. Rollback Procedure

If a critical failure occurs within the first hour:

### Option A — Revert to previous image

```bash
# On VDS
ssh -p 4625 mopro@195.85.207.92

cd /opt/mopro
# List available image tags
sudo docker images ghcr.io/salihsefer36/mopro-core-svc

# Roll back to previous tag
CORE_TAG=<previous-tag> FIN_TAG=<previous-tag> JOBS_TAG=<previous-tag> \
  sudo docker compose up -d --no-deps core-svc fin-svc jobs-svc
```

### Option B — Full rollback via rollback.sh

```bash
./deploy/scripts/rollback.sh
```

### Option C — Enable maintenance mode (traffic block)

Set a CloudFlare firewall rule or page rule to return 503 while investigating.

---

## 5. Post-Launch (T+1h)

```bash
# Install backup timer if not done
ssh -p 4625 mopro@195.85.207.92 'bash /opt/mopro/deploy/scripts/install-backup.sh'

# Run readiness check again to confirm backup timer is now active
./deploy/scripts/launch-readiness.sh --section G

# Run smoke again against live traffic
cd load-tests && BASE_URL=https://api.moproshop.com ./run.sh smoke
```

---

## 6. Go / No-Go Decision Log

> Fill in before launch. Keep for the record.

| Item | Decision | Signed by | Time |
|---|---|---|---|
| All FAIL checks resolved | GO / NO-GO | | |
| Known WARNs reviewed and accepted | GO / NO-GO | | |
| Manual first-order test passed | GO / NO-GO | | |
| Rollback plan confirmed | GO / NO-GO | | |
| **FINAL GO / NO-GO** | | | |

---

*Generated by Phase 6.2 — Mopro Shop Launch Readiness*
