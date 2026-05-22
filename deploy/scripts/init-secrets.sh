#!/usr/bin/env bash
# deploy/scripts/init-secrets.sh — Interactive secret initialiser for Mopro VDS.
# Run as root after setup-server.sh. Writes /etc/mopro/.env (chmod 600, root:root).
# Safe to re-run: appends only MISSING keys (does not overwrite existing values).
set -euo pipefail

ENV_FILE="/etc/mopro/.env"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: Must run as root." >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: ${ENV_FILE} not found. Run deploy/setup-server.sh first." >&2
  exit 1
fi

# ── helpers ───────────────────────────────────────────────────────────────────

_has_key() { grep -qE "^${1}=" "${ENV_FILE}" 2>/dev/null; }

_write() {
  local key="$1" val="$2"
  if ! _has_key "${key}"; then
    printf '%s=%s\n' "${key}" "${val}" >> "${ENV_FILE}"
  fi
}

_gen_pass() {
  # 32 bytes → 43-char base64url (no =)
  head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '='
}

_prompt() {
  local key="$1" prompt_text="$2" default="${3:-}"
  if _has_key "${key}"; then
    echo "  ${key}: already set — skipping"
    return
  fi
  if [[ -n "${default}" ]]; then
    read -rp "  ${prompt_text} [${default}]: " _val
    _val="${_val:-${default}}"
  else
    read -rp "  ${prompt_text}: " _val
  fi
  _write "${key}" "${_val}"
}

_prompt_secret() {
  local key="$1" prompt_text="$2"
  if _has_key "${key}"; then
    echo "  ${key}: already set — skipping"
    return
  fi
  read -rsp "  ${prompt_text} (hidden): " _val
  echo ""
  _write "${key}" "${_val}"
}

echo ""
echo "══════════════════════════════════════════════════════════"
echo " Mopro secrets initialiser → ${ENV_FILE}"
echo "══════════════════════════════════════════════════════════"
echo " Auto-generated passwords are written for DB accounts."
echo " You will be prompted for external credentials."
echo ""

# ── §1 Auto-generate DB passwords ─────────────────────────────────────────────
echo "[1/9] Generating DB passwords..."
for _key in \
  ECOM_DB_PASSWORD LEDGER_DB_PASSWORD \
  IDENTITY_DB_PASSWORD CATALOG_DB_PASSWORD CART_DB_PASSWORD \
  ORDER_DB_PASSWORD PAYMENT_DB_PASSWORD SELLER_DB_PASSWORD \
  SEARCH_DB_PASSWORD WALLET_DB_PASSWORD COMMISSION_DB_PASSWORD \
  TREASURY_DB_PASSWORD CASHBACK_DB_PASSWORD SELLERPAYOUT_DB_PASSWORD \
  NOTIFICATION_DB_PASSWORD SUPPORT_DB_PASSWORD MEDIA_DB_PASSWORD \
  SIZEFINDER_DB_PASSWORD ANTIFRAUD_DB_PASSWORD EINVOICE_DB_PASSWORD; do
  if ! _has_key "${_key}"; then
    _write "${_key}" "$(_gen_pass)"
    echo "  ${_key}: generated"
  else
    echo "  ${_key}: already set — skipping"
  fi
done

# ── §2 Auto-generate Redis + Meili + JWT + PII ────────────────────────────────
echo "[2/9] Generating Redis / Meili / JWT / PII secrets..."
if ! _has_key REDIS_PASSWORD;   then _write REDIS_PASSWORD   "$(_gen_pass)"; echo "  REDIS_PASSWORD: generated";   fi
if ! _has_key MEILI_MASTER_KEY; then _write MEILI_MASTER_KEY "$(_gen_pass)"; echo "  MEILI_MASTER_KEY: generated"; fi
if ! _has_key JWT_SIGNING_KEY;  then _write JWT_SIGNING_KEY  "$(_gen_pass)"; echo "  JWT_SIGNING_KEY: generated";  fi
if ! _has_key PII_KEK_BASE64; then
  _kek=$(head -c 32 /dev/urandom | base64)
  _write PII_KEK_BASE64 "${_kek}"
  echo "  PII_KEK_BASE64: generated (32-byte AES-GCM key)"
fi
if ! _has_key PII_PEPPER; then _write PII_PEPPER "$(_gen_pass)"; echo "  PII_PEPPER: generated"; fi
if ! _has_key ADMIN_INTERNAL_TOKEN; then _write ADMIN_INTERNAL_TOKEN "$(_gen_pass)"; echo "  ADMIN_INTERNAL_TOKEN: generated"; fi

# ── §3 Caddy / TLS ────────────────────────────────────────────────────────────
echo "[3/9] Caddy..."
_write CADDY_EMAIL "sefersalih017@gmail.com"
echo "  CADDY_EMAIL: sefersalih017@gmail.com"

# ── §4 Market + locale (TR launch defaults) ───────────────────────────────────
echo "[4/9] Market defaults (TR launch)..."
_write ENV "production"
_write MARKET "TR"
_write DEFAULT_CURRENCY "TRY"
_write DEFAULT_LOCALE "tr-TR"
_write DEFAULT_CASHBACK_CURRENCY "TRY_COIN"
_write DATA_REGION "eu-central-1"
_write COIN_LICENSE_JURISDICTION ""
_write COIN_LICENSE_AUTHORITY ""

# ── §5 PSP credentials ────────────────────────────────────────────────────────
echo "[5/9] PSP credentials (Sipay TR launch)..."
_write PSP_PROVIDER "sipay"
_prompt PSP_API_KEY        "Sipay API key"
_prompt_secret PSP_SECRET  "Sipay secret"
_prompt PSP_MERCHANT_ID    "Sipay merchant ID"
_prompt_secret PSP_WEBHOOK_SECRET "Sipay webhook secret"
_prompt SIPAY_BASE_URL     "Sipay base URL" "https://app.sipay.com.tr/ccpayment"
_write SIPAY_APP_ID        "REPLACE_ME"
_write SIPAY_APP_SECRET    "REPLACE_ME"
_write SIPAY_MERCHANT_KEY  "REPLACE_ME"
_write SIPAY_MERCHANT_ID   "REPLACE_ME"

# ── §6 SMS providers (optional — press Enter to skip each) ───────────────────
echo "[6/9] SMS providers (press Enter to skip each)..."
_prompt NETGSM_USERNAME    "Netgsm username" ""
_prompt_secret NETGSM_PASSWORD    "Netgsm password"
_prompt NETGSM_HEADER      "Netgsm sender header (approved alphanumeric)" ""
_prompt NETGSM_API_URL     "Netgsm API URL" "https://api.netgsm.com.tr/sms/send/get"
_prompt ILETIMERKEZI_USERNAME "İletimerkezi username" ""
_prompt_secret ILETIMERKEZI_PASSWORD "İletimerkezi password"
_prompt ILETIMERKEZI_SENDER "İletimerkezi sender name" ""
_write SMS_PROVIDER "mock"

# ── §7 Hetzner Storage Box backup ────────────────────────────────────────────
echo "[7/9] Hetzner Storage Box backup..."
_prompt HETZNER_STORAGEBOX_HOST "Hetzner Storage Box hostname (e.g. uXXXXXX.your-storagebox.de)"
_prompt HETZNER_STORAGEBOX_USER "Hetzner Storage Box SSH username"
_prompt HETZNER_STORAGEBOX_PORT "Hetzner Storage Box SSH port" "23"
_prompt HETZNER_STORAGEBOX_PATH "Remote backup path (e.g. /backups/mopro)" "/backups/mopro"
_prompt_secret RESTIC_PASSWORD  "Restic repository passphrase (SAVE THIS — cannot recover without it)"
_write HEALTHCHECK_BACKUP_UUID ""

# ── §7 Grafana Cloud (optional) ───────────────────────────────────────────────
echo "[8/9] Grafana Cloud (press Enter to skip each)..."
_prompt GRAFANA_PROM_USER  "Grafana Prometheus user ID" ""
_prompt_secret GRAFANA_PROM_PASS  "Grafana Prometheus API key"
_prompt GRAFANA_LOKI_USER  "Grafana Loki user ID" ""
_prompt_secret GRAFANA_LOKI_PASS  "Grafana Loki API key"
_prompt GRAFANA_TEMPO_USER "Grafana Tempo user ID" ""
_prompt_secret GRAFANA_TEMPO_PASS "Grafana Tempo API key"

# ── §8 Slack / PagerDuty (optional) ──────────────────────────────────────────
echo "[9/9] Slack / PagerDuty (press Enter to skip each)..."
_prompt SLACK_WEBHOOK            "Slack webhook URL" ""
_prompt SLACK_PANIC_WEBHOOK      "Slack panic webhook URL" ""
_prompt SLACK_DLQ_WEBHOOK_URL    "Slack DLQ webhook URL" ""
_prompt PAGERDUTY_ROUTING_KEY    "PagerDuty routing key" ""

# ── Backblaze B2 (optional) ───────────────────────────────────────────────────
_write B2_KEY_ID  ""
_write B2_APP_KEY ""
_write B2_BUCKET  "mopro-backups"

# ── Service connectivity (constructed from generated passwords) ───────────────
# These are read directly by the Go binaries at startup.
_ecom_pass=$(grep "^ECOM_DB_PASSWORD=" "${ENV_FILE}" | cut -d= -f2-)
_ledger_pass=$(grep "^LEDGER_DB_PASSWORD=" "${ENV_FILE}" | cut -d= -f2-)
_write REDIS_ADDR              "redis:6379"
_write LEDGER_DATABASE_URL     "postgres://ledger_admin:${_ledger_pass}@pgbouncer-ledger:5432/mopro_ledger?sslmode=disable"
_write NOTIFICATION_DATABASE_URL "postgres://ecom_admin:${_ecom_pass}@pgbouncer-ecom:5432/mopro_ecom?sslmode=disable"

# ── Redis stream MAXLEN defaults ──────────────────────────────────────────────
_write REDIS_STREAM_MAXLEN_ECOM_ORDER_DELIVERED_V1  "25000"
_write REDIS_STREAM_MAXLEN_ECOM_PAYMENT_CAPTURED_V1 "25000"
_write REDIS_STREAM_MAXLEN_FIN_CASHBACK_PAYMENT_POSTED_V1 "10000"
_write REDIS_STREAM_MAXLEN_FIN_SELLER_PAYOUT_POSTED_V1    "10000"

# ── Misc operational ──────────────────────────────────────────────────────────
_write HEALTHCHECK_RESTORE_UUID         ""
_write HEALTHCHECK_DISK_HYGIENE_UUID    ""
_write HEALTHCHECK_LEDGER_RECONCILE_UUID ""
_write HEALTHCHECK_CASHBACK_CRON_UUID   ""
_write HEALTHCHECK_SELLER_PAYOUT_CRON_UUID ""
_write RECONCILE_DATABASE_URL           ""
_write LEDGER_RECONCILE_DRY_RUN         "false"
_write LEDGER_RECONCILE_TZ              "Europe/Istanbul"
_write BETTERSTACK_INCIDENT_API         ""
_write PAGERDUTY_API                    ""

# ── Shipping TR launch placeholders ──────────────────────────────────────────
_write SHIPPING_DEFAULT "aras"
for _k in ARAS_API_KEY YURTICI_API_KEY SURAT_API_KEY MNG_API_KEY \
           HEPSIJET_CLIENT_ID HEPSIJET_CLIENT_SECRET PTT_API_KEY; do
  _write "${_k}" "REPLACE_ME"
done

chown root:mopro "${ENV_FILE}"
chmod 640 "${ENV_FILE}"

echo ""
echo "══════════════════════════════════════════════════════════"
echo " ${ENV_FILE} written — chmod 640 root:mopro"
echo " IMPORTANT: back up the Restic passphrase offline now."
echo "══════════════════════════════════════════════════════════"
