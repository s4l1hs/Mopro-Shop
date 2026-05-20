#!/usr/bin/env bash
# deploy/setup-server.sh — Idempotent Debian 13 (trixie) VDS bootstrap for Mopro.
# Run as root on the VDS. Safe to re-run.
# PRE-CONDITIONS: mopro user exists; sshd is already listening on port 4625.
set -euo pipefail

MOPRO_USER="mopro"
SSH_PORT=4625
MOPRO_DIR="/opt/mopro"
DATA_DIR="${MOPRO_DIR}/data"

# ── §1 Root check ─────────────────────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: Must run as root." >&2
  exit 1
fi

# ── §2 OS guard: Debian 13 (trixie) only ─────────────────────────────────────
if [[ ! -f /etc/os-release ]]; then
  echo "ERROR: /etc/os-release not found. Only Debian 13 (trixie) is supported." >&2
  exit 1
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID:-}" != "debian" ]] || [[ "${VERSION_CODENAME:-}" != "trixie" ]]; then
  echo "ERROR: Requires Debian 13 (trixie). Detected: ${ID:-unknown} ${VERSION_CODENAME:-unknown}." >&2
  exit 1
fi
echo "[1/13] OS verified: Debian 13 trixie"

# ── §3 User guard: mopro must already exist ───────────────────────────────────
if ! id "${MOPRO_USER}" &>/dev/null; then
  echo "ERROR: User '${MOPRO_USER}' does not exist." >&2
  echo "       Provision the user via your VDS provider console before running this script." >&2
  exit 1
fi
echo "[2/13] User '${MOPRO_USER}' verified"

# ── §4 SSH port guard: must already be on 4625 ───────────────────────────────
_ssh_port=$(grep -E '^Port[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null \
            | awk '{print $2}' | head -1 || true)
if [[ "${_ssh_port:-}" != "${SSH_PORT}" ]]; then
  echo "ERROR: /etc/ssh/sshd_config Port is '${_ssh_port:-not set}', expected ${SSH_PORT}." >&2
  echo "       Set 'Port ${SSH_PORT}' in sshd_config and restart sshd BEFORE running this script." >&2
  exit 1
fi
echo "[3/13] SSH port ${SSH_PORT} verified"

# ── §5 System packages ────────────────────────────────────────────────────────
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release \
  git jq unzip htop \
  ufw fail2ban \
  restic shellcheck \
  nftables iptables
echo "[4/13] System packages installed"

# ── §6 Docker (trixie repo, bookworm fallback) ────────────────────────────────
if ! command -v docker &>/dev/null; then
  _codename="trixie"
  _probe_url="https://download.docker.com/linux/debian/dists/${_codename}/Release"
  if ! curl -fsS --max-time 8 "${_probe_url}" -o /dev/null 2>/dev/null; then
    echo "  Docker trixie repo not yet available — falling back to bookworm packages"
    _codename="bookworm"
  fi

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian ${_codename} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

if ! groups "${MOPRO_USER}" | grep -q '\bdocker\b'; then
  usermod -aG docker "${MOPRO_USER}"
fi
systemctl enable --now docker
echo "[5/13] Docker installed and enabled"

# ── §7 UFW (nftables backend on Debian 13) ───────────────────────────────────
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment 'SSH Mopro custom port'
ufw allow 80/tcp            comment 'HTTP Caddy redirect'
ufw allow 443/tcp           comment 'HTTPS Caddy TLS'
ufw --force enable
echo "[6/13] UFW configured (ports: ${SSH_PORT}, 80, 443)"

# ── §8 fail2ban ───────────────────────────────────────────────────────────────
cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled  = true
port     = 4625
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
JAIL

systemctl enable --now fail2ban
systemctl restart fail2ban
echo "[7/13] fail2ban configured (monitoring port 4625)"

# ── §9 Directory structure ────────────────────────────────────────────────────
for _dir in \
  "${MOPRO_DIR}" \
  "${MOPRO_DIR}/deploy" \
  "${DATA_DIR}/postgres-ecom" \
  "${DATA_DIR}/postgres-ledger" \
  "${DATA_DIR}/postgres-config" \
  "${DATA_DIR}/redis" \
  "${DATA_DIR}/meili" \
  "${MOPRO_DIR}/bin" \
  "${MOPRO_DIR}/bin/prev" \
  "${MOPRO_DIR}/logs" \
  "${MOPRO_DIR}/backups" \
  /etc/mopro; do
  mkdir -p "${_dir}"
  chown "${MOPRO_USER}:${MOPRO_USER}" "${_dir}"
done
chmod 750 /etc/mopro
chown root:root /etc/mopro

# Redis container runs as UID 999 (bypasses root entrypoint with user: 999:999).
# Meilisearch container runs as UID 1000 (same pattern).
chown -R 999:999   "${DATA_DIR}/redis"
chown -R 1000:1000 "${DATA_DIR}/meili"
echo "[8/13] Directory tree under ${MOPRO_DIR} created"

# ── §10 /etc/mopro/.env (secrets file) ───────────────────────────────────────
if [[ ! -f /etc/mopro/.env ]]; then
  touch /etc/mopro/.env
  echo "  NOTE: /etc/mopro/.env is empty — run deploy/scripts/init-secrets.sh next."
fi
# root:mopro 640 — mopro user (running docker compose) needs read access
chown root:mopro /etc/mopro/.env
chmod 640 /etc/mopro/.env

# Symlink at deploy/.env so docker compose (run from deploy/) resolves env_file: [.env]
if [[ ! -L "${MOPRO_DIR}/deploy/.env" ]] && [[ ! -f "${MOPRO_DIR}/deploy/.env" ]]; then
  ln -sf /etc/mopro/.env "${MOPRO_DIR}/deploy/.env"
fi
# Also symlink at MOPRO_DIR root for convenience
if [[ ! -L "${MOPRO_DIR}/.env" ]] && [[ ! -f "${MOPRO_DIR}/.env" ]]; then
  ln -sf /etc/mopro/.env "${MOPRO_DIR}/.env"
fi
echo "[9/13] /etc/mopro/.env ready (chmod 640 root:mopro)"

# ── §11 Hetzner Storage Box backup SSH key ────────────────────────────────────
_ssh_dir="/home/${MOPRO_USER}/.ssh"
_key="${_ssh_dir}/mopro_hetzner_backup"
mkdir -p "${_ssh_dir}"
chown "${MOPRO_USER}:${MOPRO_USER}" "${_ssh_dir}"
chmod 700 "${_ssh_dir}"
if [[ ! -f "${_key}" ]]; then
  sudo -u "${MOPRO_USER}" ssh-keygen -t ed25519 \
    -C "mopro-backup@$(hostname)" \
    -f "${_key}" -N ""
  echo ""
  echo "  *** Add this public key to your Hetzner Storage Box authorized_keys: ***"
  cat "${_key}.pub"
  echo ""
fi
echo "[10/13] Hetzner backup SSH key at ${_key}"

# ── §12 Restic ────────────────────────────────────────────────────────────────
# Cannot init repo until /etc/mopro/.env is populated. Skipped here.
echo "[11/13] Restic installed — run 'restic init' after populating /etc/mopro/.env"

# ── §13 Systemd units hint ────────────────────────────────────────────────────
echo "[12/13] Systemd units — install after first deploy:"
echo "  cp /opt/mopro/deploy/systemd/*.{service,timer} /etc/systemd/system/"
echo "  systemctl daemon-reload && systemctl enable --now mopro-backup.timer"

# ── §14 Summary ───────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Mopro VDS bootstrap complete — $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "════════════════════════════════════════════════════════════════"
echo " Next steps:"
echo "  1. deploy/scripts/init-secrets.sh      # populate /etc/mopro/.env"
echo "  2. make deploy SERVER=mopro@195.85.207.92  # from dev machine"
echo "  3. Install systemd units (see §13 above)"
echo "════════════════════════════════════════════════════════════════"
echo "[13/13] Done"
