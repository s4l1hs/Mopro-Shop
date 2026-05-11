# DISASTER_RECOVERY.md — Crash & Recovery Runbooks

This file is action-oriented. When a runbook fires, follow it step-by-step. Do not improvise.

## 1. Severity Levels

| SEV | Meaning | Examples | Response |
|---|---|---|---|
| SEV1 | User money or data integrity at risk | Ledger invariant violated, user funds inaccessible, data corruption | Phone call to on-call; full team mobilized |
| SEV2 | Major capability lost | Checkout broken, login broken, payments down | Page on-call; respond < 15 min |
| SEV3 | Partial degradation | Search slow, push notifications delayed | Slack alert; respond < 2 hours |

Every SEV1 and SEV2 needs a blameless post-mortem within 5 business days.

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

1. Postgres reload picks up `default_transaction_read_only = on` for all DBs.
2. Writes return `ERROR: cannot execute in a read-only transaction` to apps.
3. Apps surface "system maintenance" UI.
4. Slack panic webhook fires.
5. The script does NOT auto-undo. Operator must verify cleanup is safe BEFORE switching back.

### 2.3 disk-watch.sh

```bash
#!/usr/bin/env bash
# /opt/mopro/scripts/disk-watch.sh
# 5 dakikada bir cron ile çalışır
set -euo pipefail
USE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

if [ "$USE" -ge 92 ]; then
    docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
      "ALTER SYSTEM SET default_transaction_read_only = on;" || true
    docker exec postgres-ecom psql -U ecom_admin -c "SELECT pg_reload_conf();" || true
    docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
      "ALTER SYSTEM SET default_transaction_read_only = on;" || true
    docker exec postgres-ledger psql -U ledger_admin -c "SELECT pg_reload_conf();" || true
    curl -X POST "$SLACK_PANIC_WEBHOOK" -d "{\"text\":\"PANIC: Disk %${USE} - Postgres read-only modda\"}"
elif [ "$USE" -ge 85 ]; then
    curl -X POST "$BETTERSTACK_INCIDENT_API" -d "Disk %${USE}"
elif [ "$USE" -ge 75 ]; then
    curl -X POST "$SLACK_WEBHOOK" -d "{\"text\":\"Uyarı: Disk %${USE} - cleanup düşün\"}"
fi
```

### 2.4 Recovery steps (operator action)

```bash
# 1) Identify what is using disk
df -h /
sudo du -h --max-depth=1 /var/lib/docker /opt/mopro 2>/dev/null | sort -h

# 2) Run hygiene
sudo /opt/mopro/scripts/disk-hygiene.sh

# 3) If still high: check WAL backlog
docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
  "SELECT count(*) FROM pg_ls_dir('pg_wal/archive_status') WHERE name LIKE '%.ready'"

# 4) If WAL backlog is the cause, fix archive_command first.
#    DO NOT manually delete .ready WAL files. They are required for PITR.

# 5) Once usage < 75%, lift read-only:
docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
  "ALTER SYSTEM SET default_transaction_read_only = off;"
docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c "SELECT pg_reload_conf();"
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
  "ALTER SYSTEM SET default_transaction_read_only = off;"
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c "SELECT pg_reload_conf();"

# 6) Verify writes work, then close incident.
```

### 2.5 disk-hygiene.sh (weekly cron + on-demand)

```bash
#!/usr/bin/env bash
# /opt/mopro/scripts/disk-hygiene.sh
# Cron: 0 4 * * 1
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

## 3. Stuck Saga / Outbox Backlog Runbook

### 3.1 Symptoms

- `mopro outbox list --unpublished` returns rows older than 5 minutes.
- Order completed but coin not credited to seller.
- Withdraw stuck in PENDING.

### 3.2 Diagnosis

```bash
# Show pending events
mopro outbox list --unpublished

# Inspect the saga of a specific order
mopro saga inspect <order_id>
mopro saga timeline <order_id>

# Logs
docker logs --tail 200 fin-svc | grep -i error
docker logs --tail 200 jobs-svc | grep -i error

# Redis Streams group state
docker exec redis redis-cli -a "$REDIS_PASSWORD" XINFO GROUPS ecom.order.completed.v1
```

### 3.3 Replay procedure

```bash
# Dry run first — ALWAYS
mopro outbox replay --since "1 hour ago" --dry-run

# Confirm if the dry run looks correct
mopro outbox replay --since "1 hour ago" --confirm
```

The CLI uses each row's `idempotency_key`, so re-publishing is safe. Consumers will skip already-applied events.

### 3.4 Single event replay

```bash
mopro outbox replay <event_id>
```

### 3.5 If consumer is broken (not just down)

1. Roll back consumer service to previous image:
   ```bash
   cd /opt/mopro
   ./scripts/deploy.sh "$(cat .previous-tag)"
   ```
2. Wait for outbox-publisher to drain.
3. If drained: investigate consumer in staging.
4. If not draining: page on-call.

## 4. Backup & Restore (Backblaze B2)

### 4.1 Backup architecture

| Source | Frequency | Tool | Destination |
|---|---|---|---|
| postgres-ecom WAL | continuous (5 min batch) | wal-push | B2 `mopro-backups/wal-ecom` |
| postgres-ledger WAL | continuous (5 min batch) | wal-push | B2 `mopro-backups/wal-ledger` |
| Both Postgres pg_dumpall | daily 03:00 | restic | B2 `mopro-backups/full` |
| Redis RDB + Meilisearch dump | weekly | restic | B2 `mopro-backups/aux` |

Retention: daily 30, weekly 12, monthly 12.

### 4.2 Restore procedure (full VDS loss)

Time budget: < 4 hours.

```bash
# 1) New VDS provisioned, Docker installed, repo cloned to /opt/mopro

# 2) Restore secrets (.env not in Git: pull from a sealed source: 1Password etc.)
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
gunzip -c /tmp/restore/*/postgres-ecom.sql.gz \
  | docker exec -i postgres-ecom psql -U ecom_admin

gunzip -c /tmp/restore/*/postgres-ledger.sql.gz \
  | docker exec -i postgres-ledger psql -U ledger_admin

# 6) Replay WAL up to last available point.
# Configure recovery.signal + restore_command in postgresql.conf
# Start in recovery mode; it will fetch WAL from B2 until exhausted.

# 7) Bring up the rest
docker compose up -d

# 8) Verify
mopro ledger reconcile --dry-run
docker compose ps
curl -sf https://api.moproshop.com/healthz
```

### 4.3 Restore drill — MANDATORY weekly

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
gunzip -c /tmp/restore-test/*/postgres-ecom.sql.gz \
  | docker exec -i pg-restore-test psql -U postgres
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

## 5. Postgres Crash / Restart

```bash
# 1) Identify which one
docker compose ps

# 2) Check logs
docker logs --tail 200 postgres-ecom
docker logs --tail 200 postgres-ledger

# 3) If clean shutdown: restart
docker compose restart postgres-ecom

# 4) If unclean shutdown: Postgres replays WAL on startup.
#    Watch for completion: "database system is ready to accept connections"

# 5) After restart, verify ledger invariant immediately
mopro ledger reconcile --dry-run
```

If WAL replay fails (unlikely with append-only design), escalate to SEV1 and follow § 4.2.

## 6. Caddy Down

```bash
docker compose restart caddy
docker logs --tail 100 caddy

# Common cause: invalid Caddyfile after an edit. Validate:
docker run --rm -v /opt/mopro/caddy/Caddyfile:/etc/caddy/Caddyfile caddy:2 \
  caddy validate --config /etc/caddy/Caddyfile
```

## 7. Redis Down

```bash
docker compose restart redis
# AOF will replay on startup. Streams data preserved within configured retention.
# Outbox-publisher resumes; events queued in outbox table while Redis was down.
```

## 8. mopro CLI Cheat Sheet

```bash
mopro outbox list [--aggregate <name>] [--unpublished] [--since "<duration>"]
mopro outbox replay <event_id>
mopro outbox replay --since "<duration>" [--dry-run|--confirm]
mopro saga inspect <order_id>
mopro saga timeline <order_id>
mopro ledger reconcile [--dry-run|--confirm]
mopro ledger lock-account <account_id> --reason "<text>"
mopro ledger unlock-account <account_id>
mopro health all
```

## 9. Status Page Updates

Public status page hosted on Better Stack. ALWAYS update during SEV1/SEV2:
- Initial post within 5 minutes ("investigating").
- Update every 30 minutes minimum.
- Resolution post when verified.

## 10. After Every Incident

1. Open `/docs/postmortems/<date>-<slug>.md`.
2. Sections: Summary, Timeline, Impact, Root Cause, Detection, Resolution, Action Items.
3. Blameless. Focus on systems, not people.
4. File action items as issues with owner + due date.
