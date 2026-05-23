#!/usr/bin/env bash
# install-disk-watch.sh — installs and enables the disk-watch systemd timer on the VDS.
# Run once as root after deploy.sh has copied the repo to /opt/mopro.
set -euo pipefail

REPO_ROOT="/opt/mopro"
SYSTEMD_DIR="/etc/systemd/system"
SCRIPT_SRC="${REPO_ROOT}/deploy/scripts/disk-watch.sh"
SCRIPT_DST="/opt/mopro/deploy/scripts/disk-watch.sh"

echo "[install-disk-watch] Checking prerequisites..."
command -v redis-cli  >/dev/null 2>&1 || { echo "ERROR: redis-cli not found — install redis-tools"; exit 1; }
command -v docker     >/dev/null 2>&1 || { echo "ERROR: docker not found"; exit 1; }
command -v curl       >/dev/null 2>&1 || { echo "ERROR: curl not found"; exit 1; }

# Ensure script is executable.
chmod +x "$SCRIPT_SRC"

# Create log directory.
mkdir -p /var/log
touch /var/log/disk-watch.log
chown mopro:mopro /var/log/disk-watch.log 2>/dev/null || true

# Create state directory.
mkdir -p /var/run/disk-watch
chown mopro:mopro /var/run/disk-watch 2>/dev/null || true

# Install systemd units.
cp "${REPO_ROOT}/deploy/systemd/disk-watch.service" "${SYSTEMD_DIR}/disk-watch.service"
cp "${REPO_ROOT}/deploy/systemd/disk-watch.timer"   "${SYSTEMD_DIR}/disk-watch.timer"

systemctl daemon-reload
systemctl enable  disk-watch.timer
systemctl start   disk-watch.timer

echo "[install-disk-watch] Timer status:"
systemctl status disk-watch.timer --no-pager || true

echo "[install-disk-watch] Done. Next fire:"
systemctl list-timers disk-watch.timer --no-pager | tail -2 || true
