# Runbook: Backup Failure

**Trigger:** PagerDuty `mopro-backup-failed` alert, Slack `:x: Mopro backup FAILED`, or Healthchecks.io grace period expired for `HEALTHCHECK_BACKUP_UUID`

**Severity:** SEV2 — data loss risk if unresolved before next backup window

---

## 1. Quick Triage

```bash
# Check last backup run status
journalctl -u mopro-backup --since "24h ago" --no-pager | tail -50

# Check timer status
systemctl status mopro-backup.timer
systemctl list-timers mopro-backup.timer --no-pager

# Re-run manually to see live output
sudo -u mopro bash /opt/mopro/deploy/scripts/backup-postgres.sh
```

---

## 2. Common Failure Modes

### 2a. pg_dump failed

**Symptom:** `pg_dump postgres-ecom failed` or `pg_dump postgres-ledger failed`

```bash
# Check if containers are running
docker ps | grep postgres

# Test dump manually
docker exec -e PGPASSWORD="$(grep ECOM_DB_PASSWORD /opt/mopro/.env | cut -d= -f2)" \
    postgres-ecom pg_dump -U ecom_admin -d mopro_ecom --format=custom -f /dev/null
```

**Fix:** Resolve the Postgres issue first (see §3 of DISASTER_RECOVERY.md). Once containers are healthy, re-run backup manually.

### 2b. B2 authentication failure

**Symptom:** `restic backup to B2 failed` — usually `401 Unauthorized` or `403 Forbidden`

```bash
# Test B2 connectivity
B2_KEY_ID=$(grep B2_KEY_ID /opt/mopro/.env | cut -d= -f2)
B2_APP_KEY=$(grep B2_APP_KEY /opt/mopro/.env | cut -d= -f2)
B2_BUCKET=$(grep B2_BUCKET /opt/mopro/.env | cut -d= -f2)

B2_ACCOUNT_ID=$B2_KEY_ID B2_ACCOUNT_KEY=$B2_APP_KEY \
    RESTIC_PASSWORD=$(grep RESTIC_PASSWORD /opt/mopro/.env | cut -d= -f2) \
    restic -r "b2:${B2_BUCKET}:mopro-backups" snapshots
```

**Fix:** Rotate B2 application key in Backblaze console; update `B2_APP_KEY` in `/opt/mopro/.env`; re-run backup.

### 2c. Hetzner SSH failure (non-fatal)

**Symptom:** Slack warning `Hetzner backup failed (B2 OK)` — B2 backup still succeeded.

This is non-critical (B2 is primary). Investigate separately:

```bash
ssh -p 23 -i /home/mopro/.ssh/mopro_hetzner_backup mopro-hetzner-backup "ls"
```

**Fix:** Verify Storage Box credentials in Hetzner console; check SSH key hasn't been revoked.

### 2d. restic check failed

**Symptom:** `restic check B2 failed`

```bash
# Full check with verbose output
RESTIC_PASSWORD=$(grep RESTIC_PASSWORD /opt/mopro/.env | cut -d= -f2) \
B2_ACCOUNT_ID=$(grep B2_KEY_ID /opt/mopro/.env | cut -d= -f2) \
B2_ACCOUNT_KEY=$(grep B2_APP_KEY /opt/mopro/.env | cut -d= -f2) \
    restic -r "b2:$(grep B2_BUCKET /opt/mopro/.env | cut -d= -f2):mopro-backups" \
    check --read-data 2>&1 | tail -30
```

**Fix:** A failed full-data check is a SEV1 — escalate immediately. Backups may be corrupt. Start emergency restore procedure.

### 2e. RESTIC_PASSWORD not set

**Symptom:** `FATAL: RESTIC_PASSWORD is not set`

**Fix:** Generate and set: `openssl rand -base64 32` → add to `/opt/mopro/.env` → run `install-backup.sh`. Store the password in your password manager BEFORE running.

---

## 3. Manual Backup Run

After resolving any issue, trigger a manual backup:

```bash
sudo -u mopro bash /opt/mopro/deploy/scripts/backup-postgres.sh
```

Verify success:
```bash
# List recent snapshots
RESTIC_PASSWORD=$(grep RESTIC_PASSWORD /opt/mopro/.env | cut -d= -f2) \
B2_ACCOUNT_ID=$(grep B2_KEY_ID /opt/mopro/.env | cut -d= -f2) \
B2_ACCOUNT_KEY=$(grep B2_APP_KEY /opt/mopro/.env | cut -d= -f2) \
    restic -r "b2:$(grep B2_BUCKET /opt/mopro/.env | cut -d= -f2):mopro-backups" \
    snapshots --latest=3
```

---

## 4. Escalation

If backup has failed for **> 24 hours**, the RPO is breached. Escalate to SEV1 and consider:
1. Immediate manual backup before any planned changes.
2. Auditing last successful restore drill (see `mopro-restore-drill` journal).
3. Switching to Hetzner as primary if B2 is persistently unavailable.
