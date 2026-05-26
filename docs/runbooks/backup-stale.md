# Runbook: BackupStale

## Severity
critical

## What this means
No successful Postgres backup has been recorded in the last 26 hours (`time() - mopro_backup_last_success_timestamp_seconds > 93600`). The `mopro_backup_last_success_timestamp_seconds` metric is written by the backup script to the node_exporter textfile collector. If this metric is stale, either the backup cron is not running, the backup failed, or the metric write itself failed.

## Common causes
- The backup cron job (`backup-postgres.sh`) has not run (cron daemon stopped, cron entry removed)
- The backup script ran but failed: Backblaze B2 credentials expired, network error, disk full during dump
- The `mopro_backup.prom` textfile was not written (disk full, permission error)
- The Grafana Agent node_exporter integration lost access to the textfile directory
- The `postgres-ecom` or `postgres-ledger` container was unreachable during the backup window

## Investigation steps
1. **Check cron log**: `grep backup-postgres /var/log/syslog | tail -20` (or `journalctl -u cron | grep backup`)
2. **Run backup manually to see the error**:
   ```bash
   BACKUP_S3_BUCKET=<bucket> BACKUP_PASSPHRASE=<pass> bash /opt/mopro/scripts/backup-postgres.sh
   ```
3. **Check Healthchecks.io**: Log in to healthchecks.io and inspect the `mopro-backup-postgres` check — look at the last ping time and any failure messages
4. **Check the textfile metric**:
   ```bash
   cat /var/lib/node_exporter/textfile_collector/mopro_backup.prom
   ```
   If missing or the timestamp is old, the backup script either didn't run or failed before the metric write.
5. **Check disk space**: `df -h` — a full disk can prevent the `pg_dump` temp file from being written
6. **Check Backblaze B2 credentials**: `restic -r b2:<bucket>:<path> snapshots` — if this fails, credentials have expired or the bucket is inaccessible
7. **Check if Postgres is up**: `docker ps | grep postgres` — a stopped DB will cause the dump to fail immediately

## Mitigation
- **If cron not running**: re-add the cron entry: `crontab -e` and verify the backup cron line (check `/opt/mopro/scripts/backup-postgres.sh` for the expected schedule)
- **If B2 credentials expired**: update `RESTIC_PASSWORD` and `B2_ACCOUNT_KEY` in `/opt/mopro/.env`; re-source and re-run the backup script manually
- **If disk full**: follow `docs/runbooks/disk-critical.md` to free space, then re-run backup
- **If backup script fails**: run manually with `bash -x` to trace the failure point; fix the root cause; re-run
- **After successful manual run**: verify `mopro_backup_last_success_timestamp_seconds` is updated in the textfile and that Grafana shows a fresh timestamp

## Escalation
- Slack: #mopro-panic if backup has been stale > 48 hours (recovery point objective at risk)
- PagerDuty escalation policy: Platform → On-Call Engineer
- If a DR event is actively underway with no recent backup: escalate to Finance and engineering lead immediately

## Post-incident
- Record root cause and resolution time in incident doc
- Verify backup integrity on B2: `restic -r b2:<bucket>:<path> check`
- Verify a test restore works: restore to a temporary container, run a smoke query
- Add the failure mode to the backup script's error handling if not already covered
- Review the Healthchecks.io grace period — if it is set longer than 26h, tighten it to match the alert threshold
