#!/usr/bin/env bash
# Removes stale Docker artifacts, old log files, and expired backup snapshots.
# Run nightly via cron: 0 3 * * * /opt/mopro/scripts/disk-hygiene.sh
set -euo pipefail

log() { echo "[disk-hygiene] $(date -u +%FT%TZ) $*"; }

log "removing dangling Docker images and stopped containers"
docker image prune -f || true
docker container prune -f || true
docker volume prune -f --filter "label!=mopro.keep=true" || true

log "removing Go test cache older than 7 days"
find /tmp -name "*.test" -mtime +7 -delete 2>/dev/null || true

# TODO(mopro:placeholder): prune old restic snapshots (keep last 30 days)
# Unblocked by: backup.sh implementation and B2 credentials
log "disk-hygiene complete"
