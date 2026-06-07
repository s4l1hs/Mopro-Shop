#!/usr/bin/env bash
# deploy/scripts/install-backup.sh — One-shot VDS setup for the restic backup pipeline.
# Run as root after the repo has been placed at /opt/mopro.
#
# What it does:
#   1. Verifies / installs restic
#   2. Validates required env vars (RESTIC_PASSWORD, B2_*, HEALTHCHECK_*)
#   3. Sets up SSH config for Hetzner Storage Box (if configured)
#   4. Initialises restic repositories (B2 + Hetzner if configured)
#   5. Installs systemd units and enables timers
#   6. Runs a first backup to verify everything works end-to-end
set -euo pipefail

REPO_ROOT="/opt/mopro"
ENV_FILE="/opt/mopro/.env"
SYSTEMD_DIR="/etc/systemd/system"
MOPRO_USER="mopro"
SSH_KEY="/home/${MOPRO_USER}/.ssh/mopro_hetzner_backup"

log()  { echo "[install-backup] $*"; }
fail() { echo "[install-backup] ERROR: $*" >&2; exit 1; }

# ── Must run as root ──────────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || fail "This script must be run as root"

# ── Load env ──────────────────────────────────────────────────────────────────
[[ -f "$ENV_FILE" ]] || fail "Env file not found: $ENV_FILE. Run init-secrets.sh first."
_get_env() { grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d "'" | tr -d '"' || true; }

RESTIC_PASSWORD="${RESTIC_PASSWORD:-$(_get_env RESTIC_PASSWORD)}"
B2_KEY_ID="${B2_KEY_ID:-$(_get_env B2_KEY_ID)}"
B2_APP_KEY="${B2_APP_KEY:-$(_get_env B2_APP_KEY)}"
B2_BUCKET="${B2_BUCKET:-$(_get_env B2_BUCKET)}"
HETZNER_HOST="${HETZNER_STORAGEBOX_HOST:-$(_get_env HETZNER_STORAGEBOX_HOST)}"
HETZNER_PORT="${HETZNER_STORAGEBOX_PORT:-$(_get_env HETZNER_STORAGEBOX_PORT)}"
HETZNER_PORT="${HETZNER_PORT:-23}"
HETZNER_USER="${HETZNER_STORAGEBOX_USER:-$(_get_env HETZNER_STORAGEBOX_USER)}"
HETZNER_PATH="${HETZNER_STORAGEBOX_PATH:-$(_get_env HETZNER_STORAGEBOX_PATH)}"
HETZNER_PATH="${HETZNER_PATH:-/backups/mopro}"

# ── Validate mandatory vars ───────────────────────────────────────────────────
log "Validating environment..."
[[ -z "${RESTIC_PASSWORD:-}" ]] && fail "RESTIC_PASSWORD is not set in ${ENV_FILE}.
  Generate one with: openssl rand -base64 32
  Add it to ${ENV_FILE} as RESTIC_PASSWORD=<value>
  Then back it up to a password manager (1Password/Bitwarden) BEFORE proceeding."

[[ -z "${B2_KEY_ID:-}" ]]  && fail "B2_KEY_ID not set in ${ENV_FILE}"
[[ -z "${B2_APP_KEY:-}" ]] && fail "B2_APP_KEY not set in ${ENV_FILE}"
[[ -z "${B2_BUCKET:-}" ]]  && fail "B2_BUCKET not set in ${ENV_FILE}"

log "Environment OK."

# ── Install restic ────────────────────────────────────────────────────────────
if command -v restic &>/dev/null; then
    RESTIC_VER=$(restic version 2>/dev/null | head -1 || echo "unknown")
    log "restic already installed: ${RESTIC_VER}"
else
    log "Installing restic via apt..."
    apt-get update -qq
    apt-get install -y restic
    restic self-update || true
    log "restic installed: $(restic version | head -1)"
fi

# ── Hetzner SSH config ────────────────────────────────────────────────────────
MOPRO_HOME="/home/${MOPRO_USER}"
SSH_DIR="${MOPRO_HOME}/.ssh"
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"

if [[ -n "${HETZNER_HOST}" && -n "${HETZNER_USER}" ]]; then
    log "Configuring Hetzner SSH..."

    # Generate backup-specific key if it doesn't exist.
    if [[ ! -f "${SSH_KEY}" ]]; then
        sudo -u "${MOPRO_USER}" ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "mopro-backup@$(hostname)"
        log "Generated new SSH key at ${SSH_KEY}"
        log ""
        log "===================================================================="
        log "ACTION REQUIRED: Add the following public key to Hetzner Storage Box"
        log "(Storage Box → SSH Keys → Add Key):"
        log ""
        cat "${SSH_KEY}.pub"
        log "===================================================================="
        log "Press Enter once you have added the key to continue..."
        read -r
    fi

    # Write SSH config for the hetzner-backup host alias.
    SSH_CONFIG="${SSH_DIR}/config"
    if ! grep -q "Host mopro-hetzner-backup" "${SSH_CONFIG}" 2>/dev/null; then
        cat >> "${SSH_CONFIG}" << EOF

# Added by install-backup.sh
Host mopro-hetzner-backup
    HostName ${HETZNER_HOST}
    User ${HETZNER_USER}
    Port ${HETZNER_PORT}
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
        chmod 600 "${SSH_CONFIG}"
        chown "${MOPRO_USER}:${MOPRO_USER}" "${SSH_CONFIG}"
        log "SSH config written for mopro-hetzner-backup"
    else
        log "SSH config entry already exists for mopro-hetzner-backup"
    fi
fi

chown -R "${MOPRO_USER}:${MOPRO_USER}" "${SSH_DIR}"

# ── Initialise restic repositories ───────────────────────────────────────────
export RESTIC_PASSWORD
export B2_ACCOUNT_ID="${B2_KEY_ID}"
export B2_ACCOUNT_KEY="${B2_APP_KEY}"
# B2 native backend uses f003.backblazeb2.com download URL which is broken in eu-central-003.
# Use S3-compatible API endpoint instead (different infrastructure, working).
export AWS_ACCESS_KEY_ID="${B2_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${B2_APP_KEY}"
export GODEBUG="${GODEBUG:-netdns=go}"

B2_REPO="s3:${B2_S3_ENDPOINT:-https://s3.eu-central-003.backblazeb2.com}/${B2_BUCKET}"
HETZNER_REPO="sftp:mopro-hetzner-backup:${HETZNER_PATH}/mopro-backups"

log "Initialising B2/S3 repository (${B2_REPO})..."
{
    set +x
    if ! sudo -u "${MOPRO_USER}" \
            RESTIC_PASSWORD="${RESTIC_PASSWORD}" \
            AWS_ACCESS_KEY_ID="${B2_KEY_ID}" \
            AWS_SECRET_ACCESS_KEY="${B2_APP_KEY}" \
            GODEBUG="${GODEBUG:-netdns=go}" \
            restic -r "${B2_REPO}" snapshots --quiet 2>/dev/null; then
        sudo -u "${MOPRO_USER}" \
            RESTIC_PASSWORD="${RESTIC_PASSWORD}" \
            AWS_ACCESS_KEY_ID="${B2_KEY_ID}" \
            AWS_SECRET_ACCESS_KEY="${B2_APP_KEY}" \
            GODEBUG="${GODEBUG:-netdns=go}" \
            restic -r "${B2_REPO}" init
        log "B2/S3 repository initialised."
    else
        log "B2/S3 repository already exists."
    fi
    set -x
}

if [[ -n "${HETZNER_HOST}" && -n "${HETZNER_USER}" ]]; then
    log "Initialising Hetzner repository (${HETZNER_REPO})..."
    {
        set +x
        if ! sudo -u "${MOPRO_USER}" \
                RESTIC_PASSWORD="${RESTIC_PASSWORD}" \
                restic -r "${HETZNER_REPO}" snapshots --quiet 2>/dev/null; then
            sudo -u "${MOPRO_USER}" \
                RESTIC_PASSWORD="${RESTIC_PASSWORD}" \
                restic -r "${HETZNER_REPO}" init
            log "Hetzner repository initialised."
        else
            log "Hetzner repository already exists."
        fi
        set -x
    }
fi

# ── Snapshot directory ────────────────────────────────────────────────────────
SNAPSHOT_DIR="/var/lib/mopro/snapshots"
if [[ ! -d "${SNAPSHOT_DIR}" ]]; then
    mkdir -p "${SNAPSHOT_DIR}"
    chown "${MOPRO_USER}:${MOPRO_USER}" "${SNAPSHOT_DIR}"
    chmod 750 "${SNAPSHOT_DIR}"
    log "Created snapshot dir: ${SNAPSHOT_DIR}"
else
    log "Snapshot dir already exists: ${SNAPSHOT_DIR}"
fi

# ── Install systemd units ─────────────────────────────────────────────────────
log "Installing systemd units..."
cp "${REPO_ROOT}/deploy/systemd/mopro-backup.service"            "${SYSTEMD_DIR}/"
cp "${REPO_ROOT}/deploy/systemd/mopro-backup.timer"              "${SYSTEMD_DIR}/"
cp "${REPO_ROOT}/deploy/systemd/mopro-backup-prune.service"      "${SYSTEMD_DIR}/"
cp "${REPO_ROOT}/deploy/systemd/mopro-backup-prune.timer"        "${SYSTEMD_DIR}/"
cp "${REPO_ROOT}/deploy/systemd/mopro-snapshot.service"          "${SYSTEMD_DIR}/"
cp "${REPO_ROOT}/deploy/systemd/mopro-snapshot.timer"            "${SYSTEMD_DIR}/"
cp "${REPO_ROOT}/deploy/systemd/mopro-restore-drill.service"     "${SYSTEMD_DIR}/"
cp "${REPO_ROOT}/deploy/systemd/mopro-restore-drill.timer"       "${SYSTEMD_DIR}/"
chmod +x "${REPO_ROOT}/deploy/scripts/backup-postgres.sh"
chmod +x "${REPO_ROOT}/deploy/scripts/backup-prune.sh"
chmod +x "${REPO_ROOT}/deploy/scripts/mopro-snapshot.sh"
chmod +x "${REPO_ROOT}/deploy/scripts/restore-postgres.sh"
chmod +x "${REPO_ROOT}/deploy/scripts/restore-drill.sh"

systemctl daemon-reload
systemctl enable  mopro-snapshot.timer
systemctl enable  mopro-backup.timer
systemctl enable  mopro-backup-prune.timer
systemctl enable  mopro-restore-drill.timer
systemctl start   mopro-snapshot.timer
systemctl start   mopro-backup.timer
systemctl start   mopro-backup-prune.timer
systemctl start   mopro-restore-drill.timer

log "Timers enabled:"
systemctl list-timers mopro-snapshot.timer mopro-backup.timer mopro-backup-prune.timer mopro-restore-drill.timer --no-pager | tail -6 || true

# ── Run first backup ──────────────────────────────────────────────────────────
log ""
log "Running first backup to verify end-to-end..."
sudo -u "${MOPRO_USER}" \
    MOPRO_ENV_FILE="${ENV_FILE}" \
    bash "${REPO_ROOT}/deploy/scripts/backup-postgres.sh"

log ""
log "===================================================================="
log "install-backup.sh COMPLETE"
log ""
log "Next steps:"
log "  1. Verify RESTIC_PASSWORD is stored in your password manager."
log "  2. Check Slack for backup success notification."
log "  3. Verify Healthchecks.io shows a ping (HEALTHCHECK_BACKUP_UUID)."
log "  4. View snapshots: restic -r ${B2_REPO} snapshots"
log "  5. Confirm hourly snapshot timer: systemctl list-timers mopro-snapshot.timer"
log "  6. Run a manual snapshot: systemctl start mopro-snapshot.service"
log "  7. See docs/ops/backups.md for restore round-trip and IPv6 fix details."
log "===================================================================="
