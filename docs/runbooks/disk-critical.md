# Runbook: DiskCritical

## Severity
critical (panic routing — also fires to #mopro-panic Slack channel)

## What this means
Available disk space on the VDS root (or `/var`) filesystem has dropped below 8% for at least 5 minutes. At this level, Postgres will refuse to write new WAL segments, Docker layer operations will fail, and the service is at imminent risk of a complete write outage.

## Common causes
- Postgres WAL accumulation (long-running replication slot or high-write period without checkpoint)
- Docker image or container layer build-up (old images not pruned after deploys)
- Restic backup cache not cleaned up (`.cache/restic` growing unbounded)
- Log files not rotated (Docker JSON logs or application log files)
- Meilisearch index data growing larger than anticipated
- A runaway job writing large temporary files to disk

## Investigation steps
1. **Check overall disk usage**: `df -h` — identify which filesystem is near-full
2. **Find the biggest directories**:
   ```bash
   du -sh /var/lib/docker/* 2>/dev/null | sort -rh | head -10
   du -sh /var/lib/docker/volumes/* 2>/dev/null | sort -rh | head -10
   du -sh /opt/mopro/* 2>/dev/null | sort -rh | head -10
   ```
3. **Check Docker images**: `docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | sort -k3 -rh | head -20`
4. **Check Postgres WAL**: `docker exec postgres-ecom du -sh /var/lib/postgresql/data/pg_wal/`
5. **Check Postgres WAL slots** (if replication slots exist): `docker exec postgres-ecom psql -U mopro -c "SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) FROM pg_replication_slots;"`
6. **Check Meilisearch data**: `du -sh /var/lib/docker/volumes/*meilisearch*`
7. **Check Restic cache**: `du -sh ~/.cache/restic 2>/dev/null`
8. **Check container logs size**: `du -sh /var/lib/docker/containers/`

## Mitigation
**Immediate (reclaim space fast):**
- Prune old Docker images: `docker image prune -af --filter "until=168h"` (removes images older than 7 days)
- Prune stopped containers: `docker container prune -f`
- Prune unused volumes: `docker volume prune -f` (VERIFY no active volumes are included first)
- Clean Restic cache: `restic cache --cleanup`
- Rotate Docker JSON logs: truncate the largest log file: `truncate -s 0 /var/lib/docker/containers/<id>/<id>-json.log` (service keeps running)

**If Postgres WAL is the cause:**
- If a replication slot is holding WAL: `SELECT pg_drop_replication_slot('<slot_name>');` after confirming the downstream is gone
- Force checkpoint: `docker exec postgres-ecom psql -U mopro -c "CHECKPOINT;"`

**After reclaiming space (> 15% free):**
- Verify services are still running: `docker ps`
- Verify Postgres can write: `docker exec postgres-ecom psql -U mopro -c "SELECT 1;"`

## Escalation
- Slack: #mopro-panic (this is a panic-routing alert)
- PagerDuty escalation policy: Platform → On-Call Engineer
- If Postgres is already refusing writes: declare full outage; escalate immediately

## Post-incident
- Identify root cause of growth in incident doc
- Set up a `DiskWarning` baseline review: check if growth trend was visible in Grafana 24–48h before critical
- Add automated Docker image pruning to the deploy Makefile or a weekly cron
- Consider adding a log rotation config (`max-size`, `max-file`) to `docker-compose.prod.yml` for each service
