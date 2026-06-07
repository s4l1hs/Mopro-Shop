# Mopro Backup & Recovery

> **TL;DR** — Three tiers: hourly local snapshot → nightly restic to B2 (primary) + Hetzner SFTP (secondary) → weekly retention prune. Recovery is `pg_restore` from the snapshot dir (minutes) or `restic restore` from B2 (depends on network). Run `install-backup.sh` once per VDS; everything else is automated via systemd timers.

---

## Pipeline Overview

```
Every hour (mopro-snapshot.timer)
  └─ mopro-snapshot.sh
        pg_dump ecom + ledger  ──► /var/lib/mopro/snapshots/ecom-<TS>.dump
        redis BGSAVE + cp      ──► /var/lib/mopro/snapshots/redis-<TS>.rdb
        Retention: last 48 files per type (≈ 2 days on disk)

Every day 02:00 Istanbul (mopro-backup.timer)
  └─ backup-postgres.sh
        pg_dump ecom + ledger  ──► /tmp/mopro-backup-XXXXX/ (cleaned on exit)
        restic backup          ──► B2: b2:<BUCKET>:mopro-backups  (primary)
                               ──► Hetzner SFTP              (secondary, fail-soft)
        restic check --read-data-subset=5%
        restic forget --prune  (inline daily retention)
        Healthchecks.io ping + Slack notification

Every Sunday 04:30 Istanbul (mopro-backup-prune.timer)
  └─ backup-prune.sh
        restic forget --prune  ──► B2 (belt-and-suspenders orphan pack cleanup)
        restic forget --prune  ──► Hetzner (fail-soft)
        Slack notification with repo stats

Every Sunday 04:00 Istanbul (mopro-restore-drill.timer)
  └─ restore-drill.sh
        restic restore latest snapshot to /tmp/mopro-restore-drill-XXXXX/
        pg_restore --schema-only on both dumps
        Slack success/failure
```

---

## Systemd Units

| Unit | Type | Schedule | Script |
|------|------|----------|--------|
| `mopro-snapshot.service` | oneshot | hourly (+120s jitter) | `deploy/scripts/mopro-snapshot.sh` |
| `mopro-snapshot.timer` | timer | `OnCalendar=hourly` | — |
| `mopro-backup.service` | oneshot | 02:00 Istanbul daily | `deploy/scripts/backup-postgres.sh` |
| `mopro-backup.timer` | timer | `OnCalendar=*-*-* 02:00 Europe/Istanbul` | — |
| `mopro-backup-prune.service` | oneshot | Sun 04:30 Istanbul | `deploy/scripts/backup-prune.sh` |
| `mopro-backup-prune.timer` | timer | `OnCalendar=Sun *-*-* 04:30 Europe/Istanbul` | — |
| `mopro-restore-drill.service` | oneshot | Sun 04:00 Istanbul | `deploy/scripts/restore-drill.sh` |
| `mopro-restore-drill.timer` | timer | `OnCalendar=Sun *-*-* 04:00 Europe/Istanbul` | — |

All units are installed at `/etc/systemd/system/` on the VDS and run as `User=mopro`.

---

## First-Time Setup

Run **once per VDS** as root after the repo has been placed at `/opt/mopro`:

```bash
# On the VDS as root:
bash /opt/mopro/deploy/scripts/install-backup.sh
```

This script:
1. Installs / upgrades restic via apt
2. Validates required env vars in `/opt/mopro/.env`
3. Configures Hetzner SSH (if `HETZNER_STORAGEBOX_HOST` is set)
4. Runs `restic init` on B2 + Hetzner repositories
5. Installs and enables all four systemd units above
6. Runs the first nightly backup end-to-end

### Required env vars (in `/opt/mopro/.env`)

```
RESTIC_PASSWORD=<64-char random — store in password manager>
B2_KEY_ID=<Backblaze application key ID>
B2_APP_KEY=<Backblaze application key>
B2_BUCKET=<bucket name>
ECOM_DB_PASSWORD=<postgres-ecom admin password>
LEDGER_DB_PASSWORD=<postgres-ledger admin password>
REDIS_PASSWORD=<redis requirepass value>
SLACK_PANIC_WEBHOOK=<Slack incoming webhook URL>

# Optional — secondary destination
HETZNER_STORAGEBOX_HOST=<u123456.your-storagebox.de>
HETZNER_STORAGEBOX_PORT=23
HETZNER_STORAGEBOX_USER=<u123456>
HETZNER_STORAGEBOX_PATH=/backups/mopro

# Optional — monitoring (L4)
HEALTHCHECK_BACKUP_UUID=<hc-ping.com UUID>
PAGERDUTY_ROUTING_KEY=<PagerDuty routing key>
```

---

## Retention Policy

| Tier | Where | Keep-daily | Keep-weekly | Keep-monthly |
|------|-------|-----------|-------------|--------------|
| Local snapshots | `/var/lib/mopro/snapshots/` | 48 files per type (≈ 2 days) | — | — |
| B2 restic (nightly backup inline prune) | B2 | 7 | 4 | 12 |
| B2 restic (weekly prune) | B2 | 7 | 4 | 6 |
| Hetzner restic | Hetzner SFTP | 7 | 4 | 6 |

> The nightly and weekly prune policies differ slightly (`monthly=12` vs `monthly=6`). The nightly inline prune runs `--keep-monthly=12` for finer long-term granularity; the weekly belt-and-suspenders prune uses `--keep-monthly=6` to compact orphaned packs.

---

## Manual Triggers

```bash
# Trigger snapshot now (fast, local)
sudo systemctl start mopro-snapshot.service
journalctl -u mopro-snapshot.service -n 30

# Trigger full nightly backup now
sudo systemctl start mopro-backup.service
journalctl -u mopro-backup.service -f

# Trigger weekly prune now
sudo systemctl start mopro-backup-prune.service
journalctl -u mopro-backup-prune.service -n 50

# Run restore drill manually
sudo systemctl start mopro-restore-drill.service
journalctl -u mopro-restore-drill.service -f

# List all scheduled timers
systemctl list-timers mopro-*.timer --no-pager
```

---

## Restore Round-Trip

### Fast path — from local snapshot (minutes, no B2 involved)

```bash
# 1. Find the most recent snapshot
ls -lt /var/lib/mopro/snapshots/ecom-*.dump | head -3

# 2. Restore ecom to a new database for verification
DUMP=/var/lib/mopro/snapshots/ecom-20260525T023001Z.dump

docker exec -i postgres-ecom \
    pg_restore -U ecom_admin -d mopro_ecom_restore \
    --no-owner --no-privileges --clean --if-exists \
    < "$DUMP"

# 3. Restore ledger similarly
docker exec -i postgres-ledger \
    pg_restore -U ledger_admin -d mopro_ledger_restore \
    --no-owner --no-privileges --clean --if-exists \
    < /var/lib/mopro/snapshots/ledger-20260525T023001Z.dump

# 4. Restore Redis RDB (stop redis first)
docker stop redis
docker cp /var/lib/mopro/snapshots/redis-20260525T023001Z.rdb redis:/data/dump.rdb
docker start redis
```

### Full path — from B2 restic (requires RESTIC_PASSWORD + B2 credentials)

```bash
# On the VDS as mopro user (or with env vars exported):
source /opt/mopro/.env
export RESTIC_PASSWORD B2_ACCOUNT_ID="${B2_KEY_ID}" B2_ACCOUNT_KEY="${B2_APP_KEY}"
B2_REPO="b2:${B2_BUCKET}:mopro-backups"

# List snapshots
restic -r "${B2_REPO}" snapshots

# Restore latest snapshot to a temp dir
RESTORE_DIR=$(mktemp -d /tmp/mopro-restore-XXXXXX)
restic -r "${B2_REPO}" restore latest --target "${RESTORE_DIR}"

# Verify dump files are present
ls -lh "${RESTORE_DIR}"/

# Restore ecom dump to the running Postgres container
docker exec -i postgres-ecom \
    pg_restore -U ecom_admin -d mopro_ecom \
    --no-owner --no-privileges --clean --if-exists \
    < "${RESTORE_DIR}/ecom.dump"

# Restore ledger dump
docker exec -i postgres-ledger \
    pg_restore -U ledger_admin -d mopro_ledger \
    --no-owner --no-privileges --clean --if-exists \
    < "${RESTORE_DIR}/ledger.dump"

# Clean up
rm -rf "${RESTORE_DIR}"
```

---

## Healthchecks.io Wiring

> **Status (2026-05-25): placeholder configured — full wiring in L4.**

The `backup-postgres.sh` script already calls `hc-ping.com` when `HEALTHCHECK_BACKUP_UUID` is set in `.env`. To activate:

1. Create a check at [healthchecks.io](https://healthchecks.io) with a 26-hour grace period.
2. Copy the UUID into `/opt/mopro/.env` as `HEALTHCHECK_BACKUP_UUID=<uuid>`.
3. The script pings `/start` at job start, `/fail` on failure, and the bare UUID on success.

Snapshot and prune timers do **not** currently ping Healthchecks.io (they only send Slack). Add `HC_SNAPSHOT_UUID` / `HC_PRUNE_UUID` env vars and corresponding `curl` calls in the scripts if monitoring coverage is needed.

---

## B2 Credential Rotation

Run on the VDS as root:

```bash
# 1. Generate a new application key in Backblaze B2 console.
#    Scope to the same bucket; set key name e.g. "mopro-vds-2026-06".

# 2. Update the env file (chmod 600, root-owned):
vi /opt/mopro/.env
# Change B2_KEY_ID and B2_APP_KEY to new values.

# 3. Verify the new key works (as mopro user):
source /opt/mopro/.env
sudo -u mopro \
    RESTIC_PASSWORD="$RESTIC_PASSWORD" \
    B2_ACCOUNT_ID="$B2_KEY_ID" B2_ACCOUNT_KEY="$B2_APP_KEY" \
    restic -r "b2:${B2_BUCKET}:mopro-backups" snapshots --quiet

# 4. Revoke the old key in Backblaze console.

# 5. Run a manual backup to confirm end-to-end:
sudo systemctl start mopro-backup.service
journalctl -u mopro-backup.service -n 20
```

The systemd EnvironmentFile directive re-reads `/opt/mopro/.env` on every service invocation, so no `daemon-reload` is required after updating credentials.

---

## Known Issue: B2 IPv6 Hang on Hetzner

**Symptom:** `restic backup` hangs for 60–120 s before starting, or fails with a TCP timeout connecting to `api.backblazeb2.com`. The issue only appears on Hetzner VDS instances (dual-stack, IPv6 default).

**Root cause:** Go's net resolver prefers AAAA records over A records when both are available. The IPv6 path from Hetzner to Backblaze B2 is degraded (packet loss / high RTT). restic uses Go's net package.

**Fix applied:** Both `mopro-backup.service` and `mopro-backup-prune.service` include:

```ini
Environment="GODEBUG=netdns=go+v4"
Environment="RESTIC_PACK_SIZE=16"
```

`GODEBUG=netdns=go+v4` forces Go's pure DNS resolver to sort IPv4 addresses first. `RESTIC_PACK_SIZE=16` reduces pack size from the default 128 MB to 16 MB, improving throughput on high-latency connections.

**Escalation path (if GODEBUG fix is insufficient):**

```bash
# Force system-wide IPv4 preference for B2 hostnames
grep -qxF 'precedence ::ffff:0:0/96 100' /etc/gai.conf \
    || echo 'precedence ::ffff:0:0/96 100' >> /etc/gai.conf
```

**Diagnosis commands:**

```bash
# Check DNS resolution for B2
resolvectl query api.backblazeb2.com

# Test IPv4 vs IPv6 latency to B2
curl -6 -o /dev/null -w "IPv6: %{time_connect}s\n" https://api.backblazeb2.com/ 2>/dev/null || echo "IPv6 unreachable"
curl -4 -o /dev/null -w "IPv4: %{time_connect}s\n" https://api.backblazeb2.com/ 2>/dev/null

# Confirm GODEBUG is active in the running unit
systemctl show mopro-backup.service -p Environment
```

---

## Disk Space Budget

Snapshot dir (`/var/lib/mopro/snapshots/`) holds at most 48 × 3 file types. At typical sizes (~50 MB ecom dump, ~20 MB ledger dump, ~5 MB redis rdb) the ceiling is:

```
48 × (50 + 20 + 5) MB ≈ 3.6 GB
```

The disk-watch systemd unit alerts at 80% disk usage (configurable via `DISK_WARN_PCT` in `.env`). The snapshot dir is on the same volume as Docker data; if disk pressure occurs, reduce the retention count by lowering `48` in `mopro-snapshot.sh`.

---

## See Also

- `deploy/scripts/backup-postgres.sh` — nightly restic backup logic
- `deploy/scripts/backup-prune.sh` — weekly retention prune
- `deploy/scripts/mopro-snapshot.sh` — hourly local pg_dump + redis rdb
- `deploy/scripts/restore-drill.sh` — automated weekly restore verification
- `deploy/scripts/restore-postgres.sh` — manual restore helper
- `deploy/scripts/install-backup.sh` — one-shot VDS setup
- `docs/ops/` — other operational runbooks
