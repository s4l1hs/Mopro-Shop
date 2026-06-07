# Disaster Recovery Procedure

**Purpose:** Step-by-step guide for full platform recovery from catastrophic failure.  
**Audience:** On-call operator, CTO.

---

## RTO / RPO

| Metric | Target | Notes |
|---|---|---|
| **RTO** (Recovery Time Objective) | **30 minutes** | From "decision to restore" to "service back online with recovered data". Achievable solo. |
| **RPO** (Recovery Point Objective) | **24 hours** | Nightly backups at 02:00 Istanbul. Data written between the last backup and the disaster is lost. |

**Post-launch improvement target (Phase 6):** RPO ≤ 1 hour via WAL streaming to B2. RTO ≤ 10 min via standby replica. These are not yet implemented.

---

## Severity Levels

| SEV | Criteria | Response |
|---|---|---|
| SEV1 | Money or data integrity at risk | Phone call; full team; RTO clock starts |
| SEV2 | Major capability lost (checkout, payments, login) | Page on-call; respond < 15 min |
| SEV3 | Partial degradation | Slack; respond < 2 hours |

Every SEV1 and SEV2: blameless post-mortem within 5 business days.

---

## Scenario 1 — Database corruption or accidental data deletion

1. **Stop writes** to prevent further corruption:
   ```bash
   docker stop core-svc jobs-svc fin-svc pgbouncer-ecom pgbouncer-ledger
   ```

2. **Assess** — does the corruption affect ecom, ledger, or both?

3. **Restore** the affected cluster(s) — see `docs/runbooks/restore-from-backup.md`.

4. **Verify** double-entry invariant (ledger) and spot-check row counts.

5. **Resume** services and monitor logs for 15 minutes.

6. **Replay** any financial crons that were interrupted:
   ```bash
   docker exec fin-svc /app/app cashback list-due --month $(date -u +%Y-%m)
   docker exec fin-svc /app/app seller-payout list-due --date $(date -u +%Y-%m-%d)
   ```

---

## Scenario 2 — VDS total loss (hardware failure, provider outage)

1. **Provision** replacement VDS: 6 vCPU / 24 GB RAM / 120 GB SSD (same provider or Hetzner).

2. **Bootstrap** the OS:
   ```bash
   bash deploy/setup-server.sh
   ```

3. **Restore secrets** from password manager to `/opt/mopro/.env`:
   Required keys: `ECOM_DB_PASSWORD`, `LEDGER_DB_PASSWORD`, `JWT_SIGNING_KEY`, `PII_ENCRYPTION_KEY`,
   `RESTIC_PASSWORD`, `B2_KEY_ID`, `B2_APP_KEY`, `B2_BUCKET`, and all PSP/shipping/Slack/PD keys.

4. **Deploy application**: add `GHCR_USER`/`GHCR_PAT` (read:packages) to the new host's
   `/etc/mopro/.env`, update the `DEPLOY_HOST` GitHub secret to the new IP, then dispatch
   the **`deploy` workflow** (`verify_only=false`). See `docs/deploy.md`.

5. **Run database migrations**:
   ```bash
   bash deploy/scripts/apply-migration.sh --db ecom up
   bash deploy/scripts/apply-migration.sh --db ledger up
   ```

6. **Install backup tooling** (generates SSH key, inits restic repos, enables timers):
   ```bash
   sudo bash /opt/mopro/deploy/scripts/install-backup.sh
   ```

7. **Restore both databases**:
   ```bash
   sudo -u mopro bash /opt/mopro/deploy/scripts/restore-postgres.sh \
       --db ecom --snapshot latest --confirm YES
   sudo -u mopro bash /opt/mopro/deploy/scripts/restore-postgres.sh \
       --db ledger --snapshot latest --confirm YES
   ```

8. **Verify ledger invariant** (all balances must be 0):
   ```bash
   docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c "
   SELECT currency, SUM(CASE WHEN direction='D' THEN amount_minor ELSE -amount_minor END) AS balance
   FROM wallet_schema.ledger_entries GROUP BY currency;"
   ```

9. **Update DNS** in Cloudflare to point to the new VDS IP.

10. **Smoke test**: `curl -s https://api.moproshop.com/healthz`

11. **Monitor** for 15 minutes; replay interrupted crons if needed.

**Estimated time: 30 minutes.**

---

## Scenario 3 — Redis data loss (cache only; no financial data)

Redis is intentionally ephemeral. Cart contents, rate limits, and stock reservations are in Redis.

**Impact:** Active carts are lost (users must re-add items); in-flight reservations expire; rate limit counters reset; outbox publisher resumes from the last PostgreSQL outbox row.

**Resolution:** Redis restarts automatically. No operator action needed for data recovery. Investigate the root cause (OOM, crash).

---

## Scenario 4 — Backup unavailable when needed

1. Try B2 first: `restic -r "b2:${B2_BUCKET}:mopro-backups" snapshots`
2. If B2 fails, try Hetzner: `restic -r "sftp:mopro-hetzner-backup:${HETZNER_PATH}/mopro-backups" snapshots`
3. If both fail, check local `/opt/mopro/backups/` for legacy rsync backups.
4. If no backups are available: the platform has no restorable state from before the disaster. Escalate to SEV1, notify affected users.

---

## Backup Schedule Reference

| Job | Schedule | Source | Destinations |
|---|---|---|---|
| `mopro-backup` | Daily 02:00 Istanbul | postgres-ecom + postgres-ledger | B2 (primary) + Hetzner (secondary) |
| `mopro-restore-drill` | Weekly Sun 04:00 Istanbul | B2 latest snapshot | Throwaway docker container |

Retention: daily=7, weekly=4, monthly=12.

---

## Key File Locations

| Item | Location |
|---|---|
| Env file (secrets) | `/opt/mopro/.env` |
| Backup script | `/opt/mopro/deploy/scripts/backup-postgres.sh` |
| Restore script | `/opt/mopro/deploy/scripts/restore-postgres.sh` |
| Restore drill | `/opt/mopro/deploy/scripts/restore-drill.sh` |
| Backup log | `journalctl -u mopro-backup` |
| Drill log | `journalctl -u mopro-restore-drill` |
| Hetzner SSH key | `/home/mopro/.ssh/mopro_hetzner_backup` |
| RESTIC_PASSWORD | In `/opt/mopro/.env` AND in password manager |
