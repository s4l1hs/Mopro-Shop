# Runbook: Restore from Backup

**Use this when:** VDS disk corruption, accidental data deletion, or disaster recovery.

**RTO target:** 30 minutes from decision to restore → service back online with recovered data.  
**RPO:** Up to 24 hours (last nightly backup at 02:00 Istanbul). Data since the last backup is lost.

---

## 1. Before You Start

```bash
# 1. Check what snapshots exist
RESTIC_PASSWORD=$(grep RESTIC_PASSWORD /opt/mopro/.env | cut -d= -f2) \
B2_ACCOUNT_ID=$(grep B2_KEY_ID /opt/mopro/.env | cut -d= -f2) \
B2_ACCOUNT_KEY=$(grep B2_APP_KEY /opt/mopro/.env | cut -d= -f2) \
    restic -r "b2:$(grep B2_BUCKET /opt/mopro/.env | cut -d= -f2):mopro-backups" \
    snapshots --tag "env=prod"

# 2. Note the snapshot ID you want (or use "latest")
# 3. Decide: restore ecom, ledger, or both
```

---

## 2. Restore ecom (core-svc data)

```bash
# Full restore of mopro_ecom from latest B2 snapshot.
# This will STOP core-svc, jobs-svc, pgbouncer-ecom.
sudo -u mopro bash /opt/mopro/deploy/scripts/restore-postgres.sh \
    --db ecom \
    --snapshot latest \
    --confirm YES
```

To restore a specific snapshot:
```bash
sudo -u mopro bash /opt/mopro/deploy/scripts/restore-postgres.sh \
    --db ecom \
    --snapshot 1a2b3c4d \
    --confirm YES
```

To use Hetzner instead of B2:
```bash
sudo -u mopro bash /opt/mopro/deploy/scripts/restore-postgres.sh \
    --db ecom --snapshot latest --repo hetzner --confirm YES
```

---

## 3. Restore ledger (fin-svc financial data)

```bash
# Full restore of mopro_ledger.
# This will STOP fin-svc, pgbouncer-ledger.
sudo -u mopro bash /opt/mopro/deploy/scripts/restore-postgres.sh \
    --db ledger \
    --snapshot latest \
    --confirm YES
```

**CRITICAL:** After restoring `ledger`, verify the double-entry invariant:

```bash
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c "
SELECT currency,
       SUM(CASE WHEN direction='D' THEN amount_minor ELSE 0 END) AS debits,
       SUM(CASE WHEN direction='C' THEN amount_minor ELSE 0 END) AS credits,
       SUM(CASE WHEN direction='D' THEN amount_minor ELSE -amount_minor END) AS balance
FROM wallet_schema.ledger_entries
GROUP BY currency
ORDER BY currency;"
```

All `balance` values MUST be 0. If any are non-zero, the restored data has a ledger imbalance — escalate to SEV1 immediately.

---

## 4. Post-Restore Verification

```bash
# Verify services started
docker ps | grep -E "core-svc|fin-svc|jobs-svc|pgbouncer"

# Spot-check row counts
docker exec -e PGPASSWORD="$(grep ECOM_DB_PASSWORD /opt/mopro/.env | cut -d= -f2)" \
    postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
    "SELECT count(*) FROM identity_schema.users; SELECT count(*) FROM order_schema.orders;"

docker exec -e PGPASSWORD="$(grep LEDGER_DB_PASSWORD /opt/mopro/.env | cut -d= -f2)" \
    postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
    "SELECT count(*) FROM wallet_schema.accounts; SELECT count(*) FROM cashback_schema.plans;"

# Smoke test checkout
curl -s https://api.moproshop.com/healthz

# Check financial cron state (cashback + payouts due since backup)
docker exec fin-svc /app/app cashback list-due --month $(date -u +%Y-%m)
docker exec fin-svc /app/app seller-payout list-due --date $(date -u +%Y-%m-%d)
```

---

## 5. Fresh VDS (complete disaster)

If the entire VDS is gone and you're starting from scratch:

```bash
# 1. Provision new VDS with same specs (6 vCPU / 24 GB / 120 GB)
# 2. Run server bootstrap
bash setup-server.sh

# 3. Restore secrets from password manager to /opt/mopro/.env
# 4. Deploy application
make deploy SERVER=mopro@<new-ip>

# 5. Install backup tooling (creates repos, SSH config)
sudo bash /opt/mopro/deploy/scripts/install-backup.sh

# 6. Restore both databases
sudo -u mopro bash /opt/mopro/deploy/scripts/restore-postgres.sh \
    --db ecom --snapshot latest --confirm YES
sudo -u mopro bash /opt/mopro/deploy/scripts/restore-postgres.sh \
    --db ledger --snapshot latest --confirm YES

# 7. Verify ledger invariant (see §3 above)
# 8. Resume traffic via Cloudflare DNS update
```

Estimated time: ~30 minutes (RTO target).

---

## 6. Key Notes

- **RESTIC_PASSWORD** must match the password used when the backup was created. Store it in your password manager.
- Restoring from Hetzner uses the same password — both repos share `RESTIC_PASSWORD`.
- The restore script uses `--no-owner --no-acl`, so the restored objects are owned by the connecting Postgres user (not the original owner). This is intentional for disaster recovery.
- After a ledger restore, manually replay any cashback / seller payout cron runs that were missed: `docker exec fin-svc /app/app cashback replay --confirm`.
