# Runbook: DiskWarning

## Severity
warning

## What this means
Available disk space on the VDS root (or `/var`) filesystem has dropped below 15% for at least 10 minutes. This is an early warning — services are still running normally, but the growth trend may reach critical (`< 8%`) within hours or days without intervention.

## Common causes
- Docker images accumulating after multiple deploys without pruning
- Postgres WAL growing due to heavy write activity
- Meilisearch index growing with new product catalog entries
- Restic backup cache or temporary dump files not cleaned up
- Log files growing (Docker JSON logs, application-level logs)
- Backup script leaving a partial dump on disk after a failed run

## Investigation steps
1. **Check current usage**: `df -h` — which filesystem and how much headroom remains
2. **Find top disk consumers**:
   ```bash
   du -sh /var/lib/docker/images 2>/dev/null
   du -sh /var/lib/docker/volumes/* 2>/dev/null | sort -rh | head -10
   du -sh /opt/mopro/* 2>/dev/null | sort -rh | head -5
   ```
3. **Check Docker image count**: `docker images | wc -l` — more than ~15 images suggests pruning is overdue
4. **Check trend**: Grafana → Backup & Cron Health → "Disk Usage % Over Time" — is the trend steady growth or a sudden jump?
5. **If steady growth**: estimate time-to-critical from the trend; schedule cleanup within the next 24h
6. **If sudden jump**: look for a runaway process or a large file written recently: `find / -size +500M -newer /tmp -not -path "/proc/*" 2>/dev/null`

## Mitigation
- **Routine cleanup (no service impact)**:
  ```bash
  docker image prune -af --filter "until=168h"   # images older than 7d
  docker container prune -f
  restic cache --cleanup
  ```
- **If Postgres WAL is growing**: verify no long-running replication slots: `docker exec postgres-ecom psql -U mopro -c "SELECT slot_name, active FROM pg_replication_slots;"`
- **If large Docker log files**: add `--log-opt max-size=100m --log-opt max-file=3` to docker-compose service definitions (requires redeploy)
- **If backup left a partial dump**: `ls -lh /tmp/*.dump 2>/dev/null` and remove

## Escalation
- Slack: #mopro-eng (warning — no immediate page needed)
- If disk usage reaches 85% before cleanup is complete: escalate to `DiskCritical` runbook and involve the on-call engineer

## Post-incident
- Record what was consuming disk and the cleanup steps in incident doc
- Add Docker image pruning to the weekly maintenance cron or deploy Makefile
- Set log rotation in docker-compose if not already configured
- Review if the VDS disk upgrade is warranted based on growth trajectory
