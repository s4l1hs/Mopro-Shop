# Healthchecks.io — Mopro Platform

Six Healthchecks.io checks monitor the platform's scheduled jobs. Each check sends an alert (email/Slack/PD) if the job stops running or reports failure.

**Dashboard:** https://healthchecks.io/checks/ (log in with the project account).

---

## Checks Overview

| Check name              | UUID env var                        | Owner       | Schedule          | Grace |
|-------------------------|-------------------------------------|-------------|-------------------|-------|
| `mopro-backup`          | `HEALTHCHECK_BACKUP_UUID`           | bash        | Daily ~01:00 UTC  | 2 h   |
| `mopro-restore-drill`   | `HEALTHCHECK_RESTORE_UUID`          | bash        | Weekly Sunday     | 4 h   |
| `mopro-disk-hygiene`    | `HEALTHCHECK_DISK_HYGIENE_UUID`     | bash        | Every 60 s        | 5 min |
| `mopro-ledger-reconcile`| `HEALTHCHECK_LEDGER_RECONCILE_UUID` | fin-svc (Go)| Weekly Sunday 03:05 Istanbul | 4 h |
| `mopro-cashback-cron`   | `HEALTHCHECK_CASHBACK_CRON_UUID`    | fin-svc (Go)| 1st of month 03:00 Istanbul | 3 h |
| `mopro-seller-payout`   | `HEALTHCHECK_SELLER_PAYOUT_CRON_UUID` | fin-svc (Go) | Daily 02:30 UTC | 2 h |

All UUID values are bare UUIDs (no URL prefix). Example: `12345678-abcd-ef01-2345-6789abcdef01`.

---

## Configuration

Set in `/opt/mopro/.env` on the VDS:

```bash
HEALTHCHECK_BACKUP_UUID=<uuid>
HEALTHCHECK_RESTORE_UUID=<uuid>
HEALTHCHECK_DISK_HYGIENE_UUID=<uuid>
HEALTHCHECK_LEDGER_RECONCILE_UUID=<uuid>
HEALTHCHECK_CASHBACK_CRON_UUID=<uuid>
HEALTHCHECK_SELLER_PAYOUT_CRON_UUID=<uuid>
```

When any UUID is empty the corresponding check is silently skipped (no HTTP call). This is intentional for local dev and CI.

---

## Ping Pattern

All checks use the standard Healthchecks.io 3-ping pattern:

| Event   | URL suffix  | Meaning                              |
|---------|-------------|--------------------------------------|
| Start   | `/start`    | Job has begun; resets the timer      |
| Success | `` (empty)  | Job completed successfully           |
| Failure | `/fail`     | Job failed; sends alert immediately  |

The Go `pkg/healthcheck.Pinger` interface abstracts these three calls. Shell scripts use a local `ping_hc()` function.

---

## Check Details

### mopro-backup

- **Script:** `deploy/scripts/backup-postgres.sh`
- **Systemd:** `mopro-backup.timer` (runs at 01:00 UTC daily)
- **Pings:** `/start` at beginning, success on B2+Hetzner OK, `/fail` on any error
- **Manual trigger:** `sudo systemctl start mopro-backup.service`

### mopro-restore-drill

- **Script:** `deploy/scripts/restore-drill.sh`
- **Systemd:** `mopro-restore-drill.timer` (runs weekly, Sunday 02:00 UTC)
- **Pings:** `/start` at beginning, success after restore verified, `/fail` on error
- **Manual trigger:** `sudo systemctl start mopro-restore-drill.service`

### mopro-disk-hygiene

- **Script:** `deploy/scripts/disk-watch.sh`
- **Systemd:** `disk-watch.timer` (runs every 60 s)
- **Pings:** Success ping on every successful script execution (heartbeat pattern)
- **Note:** Disk pressure alerts go to Slack/PagerDuty separately. This check monitors that the script itself is still running.
- **Manual trigger:** `sudo systemctl start disk-watch.service`

### mopro-ledger-reconcile

- **Service:** `fin-svc` — `internal/reconcile` weekly cron
- **Schedule:** Every Sunday at 03:05 Europe/Istanbul via `robfig/cron`
- **Pings:** Start → Success/Fail from `pkg/healthcheck.Pinger` inside `WeeklyCron.runWeekly()`
- **Manual trigger:** `docker exec fin-svc /usr/local/bin/fin-svc --run-once --cron=ledger-reconcile-weekly`

### mopro-cashback-cron

- **Service:** `fin-svc` — `internal/cashback` monthly cron
- **Schedule:** 1st of each month at 03:00 Europe/Istanbul
- **Pings:** Start → Success/Fail; sends `/fail` if any plan payment fails
- **Manual trigger:** `docker exec fin-svc /usr/local/bin/fin-svc --run-once --cron=cashback-monthly`

### mopro-seller-payout

- **Service:** `fin-svc` — `internal/sellerpayout` daily cron
- **Schedule:** Daily at 02:30 UTC
- **Pings:** Start → Success/Fail; sends `/fail` if any payout has `failed` or `ambiguous` status
- **Manual trigger:** `docker exec fin-svc /usr/local/bin/fin-svc --run-once --cron=seller-payout-daily`

---

## Manual Trigger (Run-Once Mode)

`fin-svc` supports a `--run-once --cron=<name>` flag for manual execution:

```bash
# Run cashback cron against today's date
docker exec fin-svc /usr/local/bin/fin-svc --run-once --cron=cashback-monthly

# Run seller payout for today
docker exec fin-svc /usr/local/bin/fin-svc --run-once --cron=seller-payout-daily

# Run ledger reconcile
docker exec fin-svc /usr/local/bin/fin-svc --run-once --cron=ledger-reconcile-weekly
```

Run-once mode: connects to all databases using the same env vars as the long-running service, executes the job, logs structured output, and exits 0 (success) or 1 (failure). The scheduler and HTTP server are not started.

---

## Creating a New Check

1. Log in to healthchecks.io, create a new check with name `mopro-<job>`.
2. Set schedule and grace period to match the job's cadence.
3. Copy the UUID from the check detail page.
4. Add `HEALTHCHECK_<JOB>_UUID=<uuid>` to `/opt/mopro/.env` on the VDS.
5. Wire `healthcheck.NewFromUUID(os.Getenv("HEALTHCHECK_<JOB>_UUID"), ...)` in the relevant cron constructor, or add `ping_hc` to the shell script.
6. Restart the affected service: `docker compose restart <svc>`.
