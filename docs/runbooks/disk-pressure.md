# Runbook: Disk Pressure on Mopro VDS

**Audience:** On-call operator  
**Trigger:** PagerDuty alert `mopro-disk-85`, `mopro-disk-90`, or `mopro-disk-92`; or Slack `#ops` message from `mopro-disk-watch`

---

## 1. Alert Summary

| Threshold | Level | Actions taken by automation |
|---|---|---|
| 70 % | INFO | Log only |
| 80 % | WARN | Slack ping |
| 85 % | WARN | Slack + PagerDuty warning |
| 90 % | ERROR | Slack + PagerDuty error + `docker image prune -f` |
| 92 % | PANIC | All of above + `docker container prune -f --filter until=1h` + large-log truncation + Redis `SET panic:disk_full 1` |
| < 80 % | RECOVERY | Redis `DEL panic:disk_full` + PD resolve |

**Checkout impact:** When `panic:disk_full = 1` in Redis, `POST /v1/checkout/initiate` returns **503 Service Unavailable**. All other endpoints are unaffected.

---

## 2. Immediate Triage

```bash
# Check current disk usage
df -h /

# Check what is consuming space
du -sh /var/lib/docker/*   # Docker layers
du -sh /var/log/*          # Log files
du -sh /opt/mopro/logs/*   # App logs

# Is checkout disabled?
redis-cli -h redis -p 6379 GET panic:disk_full
# "1" = disabled, "(nil)" = normal
```

---

## 3. Manual Recovery Actions

### 3a. Free Docker space (safe)

```bash
# Remove unused images (automation does this at 90%)
docker image prune -f

# Remove stopped containers (automation does this at 92% with 1h filter)
docker container prune -f

# Check remaining savings before deciding on volumes
docker system df

# !! NEVER run: docker volume prune
# Volumes contain postgres-ecom and postgres-ledger data.
```

### 3b. Free log space

```bash
# Truncate large log files (> 500 MB) to 50 MB
find /var/log -name "*.log" -size +500M -exec truncate -s 50M {} \;
find /opt/mopro/logs -name "*.log" -size +500M -exec truncate -s 50M {} \; 2>/dev/null || true

# Rotate disk-watch log manually if needed
mv /var/log/disk-watch.log /var/log/disk-watch.log.bak
```

### 3c. Remove old Docker images

```bash
# Images older than 7 days that are not currently used
docker image prune -a --filter "until=168h" -f
```

### 3d. Manually clear panic mode

```bash
# Only do this when disk is safely below 75%
redis-cli -h redis -p 6379 DEL panic:disk_full
```

---

## 4. Root Cause Investigation

```bash
# Top space consumers
du -sh /var/lib/docker/volumes/*   # Should show postgres volumes
du -sh /var/lib/docker/overlay2/*  # Docker layer cache
ls -lhS /var/log/*.log             # Largest log files

# Check postgres DB size
docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -c \
  "SELECT pg_size_pretty(pg_database_size('mopro_ecom'));"

docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
  "SELECT pg_size_pretty(pg_database_size('mopro_ledger'));"
```

---

## 5. Escalation

If disk cannot be brought below 80 % within 15 minutes:
1. Notify `#ops-emergency` with current `df -h /` output.
2. Consider temporary checkout suspension (panic mode handles this automatically at 92 %).
3. Contact infrastructure owner to resize the VDS disk (Hetzner: live-resize is supported without downtime on most plans).

---

## 6. Post-Incident

After recovery:
1. Confirm `redis-cli GET panic:disk_full` returns `(nil)`.
2. Verify checkout works: `curl -X POST https://api.mopro.com/v1/checkout/initiate ...`
3. Identify root cause: log growth? Docker image accumulation? DB growth?
4. Add a permanent fix: log rotation config, image cleanup cron, or disk resize.
5. Resolve PagerDuty incident if not auto-resolved.

---

## 7. disk-watch.sh Reference

- **Location:** `/opt/mopro/deploy/scripts/disk-watch.sh`
- **Log:** `/var/log/disk-watch.log` (JSON lines; rotates at 100 MB)
- **State files:** `/var/run/disk-watch/` (hysteresis + panic_active)
- **Config env:** `DISK_WATCH_LOG`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`, `SLACK_PANIC_WEBHOOK`, `PAGERDUTY_ROUTING_KEY` — all from `/opt/mopro/.env`

```bash
# View recent log entries
tail -50 /var/log/disk-watch.log | jq .

# Check timer status
systemctl status disk-watch.timer

# Run manually (dry-run friendly: reads env, executes real actions)
sudo -u mopro /opt/mopro/deploy/scripts/disk-watch.sh

# View systemd logs
journalctl -u mopro-disk-watch -n 100 --no-pager
```
