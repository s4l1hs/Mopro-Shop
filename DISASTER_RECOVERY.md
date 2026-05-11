# DISASTER_RECOVERY.md — Crash & Recovery Runbooks v7

This file is action-oriented. When a runbook fires, follow it step-by-step. Do not improvise.

Reflects PRD v6.0 (perpetual cashback) + v7 detail packs (PSP & kargo API'ları, mobil 30+ ekran, anti-fraud ML, TR e-fatura/e-arşiv/GİB).

---

## 1. Severity Levels

| SEV | Meaning | Examples | Response |
|---|---|---|---|
| SEV1 | User money or data integrity at risk | Ledger invariant violated, cashback obligation mismatch, seller funds inaccessible, data corruption | Phone call to on-call; full team mobilized |
| SEV2 | Major capability lost | Checkout broken, cashback cron failed for entire month, seller payout cron failed for a day, login broken, payments down | Page on-call; respond < 15 min |
| SEV3 | Partial degradation | Search slow, push notifications delayed, individual cashback payment failed, individual seller payout retry needed | Slack alert; respond < 2 hours |

Every SEV1 and SEV2 needs a blameless post-mortem within 5 business days.

---

## 2. Disk Pressure Runbook

### 2.1 Thresholds

`/opt/mopro/scripts/disk-watch.sh`, cron every 5 minutes.

| Disk usage | Action |
|---|---|
| ≥ 65% | INFO log only |
| ≥ 75% | Slack alert: "consider cleanup" |
| ≥ 85% | Better Stack incident, page on-call |
| ≥ 92% | **PANIC MODE:** `ALTER SYSTEM SET default_transaction_read_only = on;` on postgres-ecom AND postgres-ledger |

### 2.2 Panic mode behavior

When the script triggers panic:

1. Postgres reload picks up `default_transaction_read_only = on` for both clusters.
2. Writes return `ERROR: cannot execute in a read-only transaction` to apps.
3. Apps surface "system maintenance" UI.
4. **Cashback monthly cron will FAIL gracefully** (it runs as a transaction; rollback is safe). Failed payments stay `scheduled` and the cron picks them up on next scheduled run.
5. **Seller payout daily cron will also FAIL gracefully** (same transactional design). Affected payouts stay `scheduled`; sellers wait an extra day at most before next cron run.
6. Slack panic webhook fires.
7. The script does NOT auto-undo. Operator must verify cleanup is safe BEFORE switching back.

### 2.3 disk-watch.sh

```bash
#!/usr/bin/env bash
set -euo pipefail
USE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

if [ "$USE" -ge 92 ]; then
    docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
      "ALTER SYSTEM SET default_transaction_read_only = on;" || true
    docker exec postgres-ecom psql -U ecom_admin -c "SELECT pg_reload_conf();" || true
    docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
      "ALTER SYSTEM SET default_transaction_read_only = on;" || true
    docker exec postgres-ledger psql -U ledger_admin -c "SELECT pg_reload_conf();" || true
    curl -X POST "$SLACK_PANIC_WEBHOOK" -d "{\"text\":\"PANIC: Disk %${USE} - Postgres read-only\"}"
elif [ "$USE" -ge 85 ]; then
    curl -X POST "$BETTERSTACK_INCIDENT_API" -d "Disk %${USE}"
elif [ "$USE" -ge 75 ]; then
    curl -X POST "$SLACK_WEBHOOK" -d "{\"text\":\"Warning: Disk %${USE} - cleanup\"}"
fi
```

### 2.4 Recovery (operator action)

```bash
df -h /
sudo du -h --max-depth=1 /var/lib/docker /opt/mopro 2>/dev/null | sort -h
sudo /opt/mopro/scripts/disk-hygiene.sh

# WAL backlog?
docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
  "SELECT count(*) FROM pg_ls_dir('pg_wal/archive_status') WHERE name LIKE '%.ready'"
# Fix archive_command first; DO NOT delete .ready files.

# Cashback table growth check
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
  "SELECT pg_size_pretty(pg_total_relation_size('cashback_schema.payments'))"
# Seller payout table growth check
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
  "SELECT pg_size_pretty(pg_total_relation_size('commission_schema.seller_payouts'))"

# When < 75%, lift read-only:
docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
  "ALTER SYSTEM SET default_transaction_read_only = off;"
docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c "SELECT pg_reload_conf();"
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
  "ALTER SYSTEM SET default_transaction_read_only = off;"
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c "SELECT pg_reload_conf();"

# If cashback or seller payout cron failed during the panic window, run them manually:
docker exec fin-svc /app/app cashback-cron --month $(date -u +%Y-%m)
docker exec fin-svc /app/app seller-payout-cron --date $(date -u +%Y-%m-%d)
```

### 2.5 disk-hygiene.sh (weekly cron)

```bash
#!/usr/bin/env bash
set -euo pipefail
docker system prune -af --volumes
find /var/lib/docker/containers/ -name "*.log" -size +100M -delete
apt-get clean
find /opt/mopro/data/postgres-ecom/pg_wal/archive_status -name "*.done" -mtime +2 -delete
find /opt/mopro/data/postgres-ledger/pg_wal/archive_status -name "*.done" -mtime +2 -delete
find /tmp -type f -atime +7 -delete
echo "Disk: $(df / | awk 'NR==2 {print $5}')"
curl -sf "https://hc-ping.com/$HEALTHCHECK_DISK_HYGIENE_UUID" || true
```

---

## 3. Cashback Cron Failure Runbook

### 3.1 Symptoms

- `mopro cashback list-due --month YYYY-MM` shows scheduled payments past their date.
- `mopro_fin_cashback_payment_total{status="failed"}` metric > 0.
- User support tickets: "Bu ay coin'im gelmedi".

### 3.2 Diagnosis

```bash
# How many payments were due, how many succeeded/failed?
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -tAc \
  "SELECT status, count(*) FROM cashback_schema.payments
   WHERE scheduled_date <= current_date GROUP BY status"

# Recent failed payments with error messages
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
  "SELECT id, plan_id, period_yyyymm, attempt_count, last_error
   FROM cashback_schema.payments
   WHERE status='failed' ORDER BY last_attempt_at DESC LIMIT 20"

# Logs
docker logs --tail 500 fin-svc | grep -i cashback
```

### 3.3 Replay Procedure

```bash
# Dry run first — ALWAYS
mopro cashback list-due --month $(date -u +%Y-%m) --dry-run

# Single payment (idempotent)
mopro cashback replay-payment <payment_id>

# Batch replay all 'failed' payments for a month
mopro cashback replay --status failed --month $(date -u +%Y-%m) --confirm
```

The CLI uses each payment's `idempotency_key`, so re-running is safe. Wallet sees no duplicate ledger entries.

### 3.4 If a Plan Was Created Incorrectly

Plans are deterministic and FROZEN. If a user reports their plan amount is wrong:

```bash
mopro cashback inspect <plan_id>
# Shows: total_amount_minor, total_months (always 24), monthly_amount_minor, status, completed payments

# Compare against what the snapshotted commission says
mopro order inspect <order_id>
# Shows: order_items[].commission_amount_minor (the snapshot the plan was derived from)

# If plan is genuinely wrong (rare; should not happen due to deterministic logic):
# 1. Cancel the plan + reverse paid coin + reverse remaining obligation
mopro cashback cancel-plan <plan_id> --reason "incorrect_calculation"

# 2. Manually create a corrected plan (rare; needs CFO approval)
# Document in /docs/postmortems/
```

### 3.5 If the Cron Itself Crashed Mid-Run

The cron processes payments individually with separate idempotency keys. A crash mid-batch leaves processed payments with `status='paid'`, unprocessed with `status='scheduled'`. Re-running the cron is safe; it picks up where it left off.

```bash
# Manual cron rerun
docker exec fin-svc /app/app cashback-cron --month $(date -u +%Y-%m)
```

---

## 4. Seller Payout Cron Failure Runbook (NEW v5)

### 4.1 Symptoms

- `mopro payout list-due --date YYYY-MM-DD` shows scheduled payouts past their unlock_at.
- `mopro_fin_sellerpayout_total{status="failed"}` metric > 0.
- `mopro_fin_sellerpayout_lag_business_days` > 4 (target is ~3).
- Seller support tickets: "Sipariş tamamlandı 5 gün oldu, ödemem hâlâ gelmedi".

### 4.2 Diagnosis

```bash
# How many payouts were due today, how many succeeded/failed/processing?
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -tAc \
  "SELECT status, count(*), SUM(amount_minor)/100 AS total_tl
   FROM commission_schema.seller_payouts
   WHERE unlock_at <= current_date GROUP BY status"

# Recent failed payouts with error messages
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
  "SELECT id, order_id, seller_id, amount_minor/100 AS tl, attempt_count, last_error, last_attempt_at
   FROM commission_schema.seller_payouts
   WHERE status='failed' ORDER BY last_attempt_at DESC LIMIT 20"

# Stuck in 'processing' (PSP webhook didn't confirm)
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
  "SELECT id, order_id, seller_id, psp_transfer_id, last_attempt_at
   FROM commission_schema.seller_payouts
   WHERE status='processing' AND last_attempt_at < now() - interval '2 hours'"

# Logs
docker logs --tail 500 fin-svc | grep -i sellerpayout
```

### 4.3 Replay Procedure

```bash
# Dry run
mopro payout list-due --date $(date -u +%Y-%m-%d) --dry-run

# Single payout (idempotent; PSP idempotency-key prevents double-transfer)
mopro payout replay <payout_id>

# Batch replay all 'failed' payouts for today
mopro payout replay --status failed --date $(date -u +%Y-%m-%d) --confirm
```

### 4.4 PSP Webhook Stuck (status='processing' too long)

If PSP confirms transfer but our webhook didn't fire (network issue, signature mismatch):

```bash
# Reconcile against PSP API
mopro payout reconcile-with-psp <payout_id>
# This calls the PSP's GET /transfers/<id> endpoint and updates our record:
# - if PSP says completed → mark as 'paid' + ledger entry already exists, no change
# - if PSP says failed → mark as 'failed' + reverse ledger entry + alert on-call
# - if PSP says still pending → no change, retry the next cron
```

### 4.5 If the Cron Itself Crashed Mid-Run

Same idempotent design as cashback; safe to rerun:

```bash
docker exec fin-svc /app/app seller-payout-cron --date $(date -u +%Y-%m-%d)
```

---

## 5. Stuck Saga / Outbox Backlog Runbook

### 5.1 Symptoms

- `mopro outbox list --unpublished` returns rows older than 5 minutes.
- Order completed but cashback plan not created.
- Order completed but seller payout not scheduled.
- Withdraw stuck in PENDING.

### 5.2 Diagnosis

```bash
mopro outbox list --unpublished
mopro saga inspect <order_id>
mopro saga timeline <order_id>
docker logs --tail 200 fin-svc | grep -i error
docker exec redis redis-cli -a "$REDIS_PASSWORD" XINFO GROUPS ecom.order.delivered.v1
```

### 5.3 Replay procedure

```bash
mopro outbox replay --since "1 hour ago" --dry-run
mopro outbox replay --since "1 hour ago" --confirm
```

The CLI uses each row's `idempotency_key`, so re-publishing is safe. Consumers will skip already-applied events. Cashback plans are guarded by `FindPlanByOrderID` idempotency check; seller payouts are guarded by `FindPayoutByKey` per (order_id, seller_id) check; replaying delivery events does not duplicate either.

### 5.4 If Consumer Is Broken

1. Roll back consumer service to previous image:
   ```bash
   cd /opt/mopro
   ./scripts/deploy.sh "$(cat .previous-tag)"
   ```
2. Wait for outbox-publisher to drain.
3. If drained: investigate consumer in staging.
4. If not draining: page on-call.

---

## 6. Backup & Restore (Backblaze B2)

### 6.1 Backup architecture

| Source | Frequency | Tool | Destination |
|---|---|---|---|
| postgres-ecom WAL | continuous (5 min batch) | wal-push | B2 `mopro-backups/wal-ecom` |
| postgres-ledger WAL | continuous (5 min batch) | wal-push | B2 `mopro-backups/wal-ledger` |
| Both Postgres pg_dumpall | daily 03:00 | restic | B2 `mopro-backups/full` |
| Redis RDB + Meilisearch dump | weekly | restic | B2 `mopro-backups/aux` |

Retention: daily 30, weekly 12, monthly 12.

The cashback schema AND seller payout schema are part of postgres-ledger and are backed up identically. Loss of cashback or seller payout data = loss of obligations to users/sellers; both are SEV1 scenarios and are the strongest reason for the weekly restore drill.

### 6.2 Restore procedure (full VDS loss)

Time budget: < 4 hours.

```bash
# 1) New VDS provisioned, Docker installed, repo cloned to /opt/mopro

# 2) Restore secrets (.env not in Git: pull from a sealed source)
cp /tmp/restored.env /opt/mopro/.env
chmod 600 /opt/mopro/.env

# 3) Pull latest restic snapshot
export RESTIC_REPOSITORY="b2:mopro-backups:/full"
export RESTIC_PASSWORD="<from secret store>"
export B2_ACCOUNT_ID=...; export B2_ACCOUNT_KEY=...

LATEST=$(restic snapshots --tag full --json | jq -r '.[-1].id')
restic restore "$LATEST" --target /tmp/restore

# 4) Start Postgres containers
docker compose up -d postgres-ecom postgres-ledger
sleep 15

# 5) Load dumps
gunzip -c /tmp/restore/*/postgres-ecom.sql.gz | docker exec -i postgres-ecom psql -U ecom_admin
gunzip -c /tmp/restore/*/postgres-ledger.sql.gz | docker exec -i postgres-ledger psql -U ledger_admin

# 6) Replay WAL up to last available point.
# Configure recovery.signal + restore_command in postgresql.conf.

# 7) Bring up the rest
docker compose up -d

# 8) Verify per-currency ledger balance + cashback obligation + seller payout sums match
mopro ledger reconcile --dry-run
mopro cashback obligation-check     # sum unpaid scheduled = liability:cashback_distribution balance
mopro payout obligation-check       # sum unpaid scheduled = liability:seller_payable balance
docker compose ps
curl -sf https://api.moproshop.com/healthz
```

### 6.3 Restore drill — MANDATORY weekly

`/opt/mopro/scripts/restore-drill.sh` runs every Sunday 04:00:

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1) Spin up an ephemeral Postgres on a stray port
docker run -d --rm --name pg-restore-test \
  -e POSTGRES_PASSWORD=test -p 6432:5432 postgres:16-alpine
sleep 10

# 2) Restore latest snapshot
LATEST=$(restic snapshots --tag full --json | jq -r '.[-1].id')
restic restore "$LATEST" --target /tmp/restore-test

# 3) Load and assert
gunzip -c /tmp/restore-test/*/postgres-ecom.sql.gz | docker exec -i pg-restore-test psql -U postgres
PRODS=$(docker exec pg-restore-test psql -U postgres -d mopro_ecom -tAc \
  "SELECT count(*) FROM catalog_schema.products")
test "$PRODS" -gt 0 || { echo "FAIL: empty restore"; exit 1; }

# 4) Cleanup
docker stop pg-restore-test
rm -rf /tmp/restore-test

# 5) Healthcheck ping (silence = alarm)
curl -sf "https://hc-ping.com/$HEALTHCHECK_RESTORE_UUID"
```

If the drill ever fails, every other change to production is BLOCKED until it passes again.

---

## 7. Postgres Crash / Restart

```bash
docker compose ps
docker logs --tail 200 postgres-ecom
docker logs --tail 200 postgres-ledger
docker compose restart postgres-ecom

# 4) If unclean shutdown: Postgres replays WAL on startup.

# 5) After restart, verify per-currency ledger invariant
mopro ledger reconcile --dry-run

# 6) Verify cashback obligation matches
mopro cashback obligation-check

# 7) Verify seller payout obligation matches
mopro payout obligation-check
```

If WAL replay fails (unlikely with append-only design), escalate to SEV1 and follow § 6.2.

---

## 8. Caddy Down

```bash
docker compose restart caddy
docker logs --tail 100 caddy
docker run --rm -v /opt/mopro/caddy/Caddyfile:/etc/caddy/Caddyfile caddy:2 \
  caddy validate --config /etc/caddy/Caddyfile
```

---

## 9. Redis Down

```bash
docker compose restart redis
# AOF replays. Outbox-publisher resumes; events queued in DB while Redis was down.
# Cashback monthly cron is unaffected (no Redis dependency for ledger writes).
# Seller payout daily cron is unaffected (PSP transfers happen via HTTPS, not Redis).
```

---

## 10. PSP Outage (Sipay/Craftgate)

If primary PSP is down:

```bash
# 1. Check status page
curl -sf https://status.sipay.com.tr   # or applicable PSP

# 2. Switch to backup PSP via env (NEW orders use new provider)
sed -i 's/PSP_PROVIDER=sipay/PSP_PROVIDER=craftgate/' /opt/mopro/.env
docker compose up -d core-svc fin-svc

# 3. Verify checkout works
curl -X POST https://api.moproshop.com/v1/orders/checkout/test

# 4. New orders use Craftgate; existing in-flight orders complete on Sipay (via stored PSP reference).
# Cashback engine is unaffected (it's downstream of order completion).
# Seller payout engine: outbound transfers initiated to NEW provider for unpaid payouts;
# already-paid payouts on old PSP retain their psp_transfer_id and stay unchanged.
```

---

## 11. Coin License Activation Day Runbook (Phase 7)

When the Coin issuance license (Dubai VARA or AB EMI) is activated:

```bash
# 1. Toggle the feature flag enabling coin → fiat conversion
mopro feature enable coin_to_fiat_conversion --jurisdiction <DUBAI|EMI>

# 2. Ensure the FX pool accounts are seeded
mopro ledger seed-account asset:fx_pool:TRY_COIN
mopro ledger seed-account asset:fx_pool:TRY

# 3. Smoke test with a small amount in staging-mirroring tenant
mopro fx test --amount 10 --user-id <test_user_id>

# 4. Update the mobile app config to surface the "Cüzdandan TL'ye Çevir" button
mopro config set --key MOBILE_SHOW_FX_CONVERT --value true

# 5. Announce to users via push notification (jobs-svc + outbox event)
mopro notification broadcast --template coin_to_fiat_now_live
```

The license activation does NOT retroactively change existing cashback plans (they remain frozen at original coin amounts and schedules). It only unlocks the conversion endpoint for users who already have coin balances.

---

## 12. mopro CLI Cheat Sheet

```bash
# Outbox
mopro outbox list [--aggregate <name>] [--unpublished] [--since "<duration>"]
mopro outbox replay <event_id>
mopro outbox replay --since "<duration>" [--dry-run|--confirm]

# Saga
mopro saga inspect <order_id>
mopro saga timeline <order_id>

# Ledger
mopro ledger reconcile [--currency <CUR>] [--dry-run|--confirm]
mopro ledger lock-account <account_id> --reason "<text>"
mopro ledger unlock-account <account_id>
mopro ledger seed-account <account_pattern>

# Cashback
mopro cashback inspect <plan_id>
mopro cashback list-due --month YYYY-MM [--dry-run]
mopro cashback replay-payment <payment_id>
mopro cashback replay --status failed --month YYYY-MM --confirm
mopro cashback cancel-plan <plan_id> --reason "<text>"
mopro cashback obligation-check    # sum unpaid scheduled vs liability:cashback_distribution balance

# Seller Payouts (NEW v5)
mopro payout inspect <payout_id>
mopro payout list-due --date YYYY-MM-DD [--dry-run]
mopro payout replay <payout_id>
mopro payout replay --status failed --date YYYY-MM-DD --confirm
mopro payout cancel <payout_id> --reason "<text>"
mopro payout reconcile-with-psp <payout_id>
mopro payout obligation-check     # sum unpaid scheduled vs liability:seller_payable balance

# Business Calendar
mopro calendar show TR --year 2026
mopro calendar add TR --date 2026-12-31 --reason "Yarım gün"

# Treasury
mopro treasury yield-summary --month YYYY-MM
mopro treasury rate-watch --threshold-drop-pct 5

# Health
mopro health all
```

---

## 13. Status Page Updates

Public status page hosted on Better Stack. ALWAYS update during SEV1/SEV2:
- Initial post within 5 minutes ("investigating").
- Update every 30 minutes minimum.
- Resolution post when verified.

For cashback cron failure: Status page entry is mandatory; users will check after not seeing their monthly notification.
For seller payout cron failure: Status page entry is mandatory; sellers will notice next-day payouts being missed.

---

## 14. After Every Incident

1. Open `/docs/postmortems/<date>-<slug>.md`.
2. Sections: Summary, Timeline, Impact, Root Cause, Detection, Resolution, Action Items.
3. Blameless. Focus on systems, not people.
4. File action items as issues with owner + due date.
5. For ledger or cashback or seller payout incidents, attach pre/post per-currency reconciliation diff.

---

**End of DISASTER_RECOVERY.md.** See LEDGER_GUIDE.md for ledger semantics, INFRASTRUCTURE.md for resource limits.
