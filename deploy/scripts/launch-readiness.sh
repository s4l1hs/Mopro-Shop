#!/usr/bin/env bash
# Phase 6.2 — Pre-launch invariant checker.
# Usage: ./launch-readiness.sh [--section A|B|C|D|E|F|G|H] [--json] [--no-ssh]
# Exit:  0 = all PASS/WARN  |  1 = at least one FAIL  |  2 = usage error
#
# Sections: A=Infrastructure B=Security C=Financial D=Observability
#           E=Performance    F=Data      G=Backups   H=Operational
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECKS_DIR="$SCRIPT_DIR/checks"

SSH_HOST="${VDS_SSH_HOST:-mopro@195.85.207.92}"
SSH_PORT="${VDS_SSH_PORT:-4625}"
export BASE_URL="${BASE_URL:-https://api.moproshop.com}"
export REPO_ROOT

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
export GREEN RED YELLOW CYAN BOLD NC

# ── Result store ──────────────────────────────────────────────────────────────
declare -a RESULTS=()
PASS_N=0; FAIL_N=0; WARN_N=0
START_TS=$(date +%s)

pass() {
  local sec="$1" chk="$2" detail="${3:-}"
  RESULTS+=("PASS|$sec|$chk|$detail")
  ((PASS_N++)) || true
  echo -e "  ${GREEN}PASS${NC}  $(printf '%-4s %-30s' "$sec" "$chk")${detail}"
}
fail() {
  local sec="$1" chk="$2" detail="${3:-}"
  RESULTS+=("FAIL|$sec|$chk|$detail")
  ((FAIL_N++)) || true
  echo -e "  ${RED}FAIL${NC}  $(printf '%-4s %-30s' "$sec" "$chk")${detail}"
}
warn() {
  local sec="$1" chk="$2" detail="${3:-}"
  RESULTS+=("WARN|$sec|$chk|$detail")
  ((WARN_N++)) || true
  echo -e "  ${YELLOW}WARN${NC}  $(printf '%-4s %-30s' "$sec" "$chk")${detail}"
}
export -f pass fail warn

# ── VDS cache helpers ─────────────────────────────────────────────────────────
VDS_CACHE=""
vds_get()    { printf '%s' "$VDS_CACHE" | grep "^${1}=" | head -1 | cut -d= -f2-; }
vds_int()    { local v; v=$(vds_get "$1"); printf '%s' "${v:-0}"; }
vds_nonempty() { local v; v=$(vds_get "$1"); [[ -n "$v" ]]; }
export VDS_CACHE
export -f vds_get vds_int vds_nonempty

# ── Argument parsing ──────────────────────────────────────────────────────────
SECTION_FILTER=""
JSON_OUT=0
NO_SSH=0
SECTION_NEXT=0

for arg in "$@"; do
  case "$arg" in
    --section) SECTION_NEXT=1 ;;
    --json)    JSON_OUT=1 ;;
    --no-ssh)  NO_SSH=1 ;;
    A|B|C|D|E|F|G|H)
      if [[ $SECTION_NEXT -eq 1 ]]; then SECTION_FILTER="$arg"; SECTION_NEXT=0; fi ;;
    --section=*) SECTION_FILTER="${arg#--section=}" ;;
    *) ;;
  esac
done

run_section() { [[ -z "$SECTION_FILTER" || "$SECTION_FILTER" == "$1" ]]; }

hdr() {
  echo -e "\n${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}  $*${NC}"
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════${NC}"
}

# ── SSH once — collect all VDS data ───────────────────────────────────────────
if [[ $NO_SSH -eq 0 ]]; then
  echo -e "${BOLD}Connecting to VDS (one-time collection)…${NC}"
  VDS_CACHE=$(ssh -p "$SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    "$SSH_HOST" 'bash -s' <<'REMOTE_EOF'
#!/bin/bash
set -uo pipefail

ENV_FILE=/opt/mopro/.env
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" 2>/dev/null || true

# ─── A: Infrastructure ────────────────────────────────────────────────────────
CRUN=$(sudo docker ps --filter status=running --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' ')
echo "CONTAINERS_RUNNING=$CRUN"

DISK=$(df / | awk 'NR==2{gsub(/%/,"",$5); print $5}')
echo "DISK_USE_PCT=$DISK"

PG=$(sudo docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -t -c \
  'SHOW server_version_num' 2>/dev/null | tr -d ' \n' || echo "0")
echo "POSTGRES_VERSION_NUM=$PG"

RPONG=$(sudo docker exec redis redis-cli -a "${REDIS_PASSWORD:-}" PING 2>/dev/null \
  | tr -d '\r\n' || echo "FAIL")
echo "REDIS_PING=$RPONG"

(timeout 3 bash -c 'echo >/dev/tcp/localhost/443' 2>/dev/null && echo "PORT_443=1") || echo "PORT_443=0"
(timeout 3 bash -c 'echo >/dev/tcp/localhost/80'  2>/dev/null && echo "PORT_80=1")  || echo "PORT_80=0"

# ─── B: Security ─────────────────────────────────────────────────────────────
ENV_EXISTS=$( [[ -f "$ENV_FILE" ]] && echo 1 || echo 0 )
echo "ENV_FILE_EXISTS=$ENV_EXISTS"

echo "JWT_KEY_LEN=${#JWT_SIGNING_KEY}"
echo "PII_KEK_LEN=${#PII_KEK_BASE64}"
echo "PII_PEPPER_LEN=${#PII_PEPPER}"
echo "RESTIC_PASS_LEN=${#RESTIC_PASSWORD}"

CMCOUNT=$(grep -c 'CHANGE_ME' "${ENV_FILE:-/dev/null}" 2>/dev/null || echo 0)
echo "CHANGE_ME_COUNT=$CMCOUNT"

echo "HC_BACKUP_UUID=${HEALTHCHECK_BACKUP_UUID:-}"
echo "HC_CASHBACK_UUID=${HEALTHCHECK_CASHBACK_CRON_UUID:-}"
echo "HC_RESTORE_UUID=${HEALTHCHECK_RESTORE_UUID:-}"
echo "HC_PAYOUT_UUID=${HEALTHCHECK_SELLER_PAYOUT_CRON_UUID:-}"
echo "GRAFANA_PROM_USER=${GRAFANA_PROM_USER:-}"
echo "GRAFANA_PROM_PASS=${GRAFANA_PROM_PASS:-}"

CADDY_F=$(find /opt/mopro /home/mopro -name 'Caddyfile' -maxdepth 5 2>/dev/null | head -1 || true)
if [[ -n "$CADDY_F" ]]; then
  FSVC=$(grep -o 'fin-svc:[0-9]*' "$CADDY_F" 2>/dev/null | head -1 || echo "")
  echo "CADDYFILE_FINSVC=${FSVC}"
else
  echo "CADDYFILE_FINSVC=missing"
fi

# ─── C: Financial ─────────────────────────────────────────────────────────────
PLAT=$(sudo docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -t -c \
  "SELECT COUNT(*) FROM wallet_schema.accounts WHERE owner_type='platform'" 2>/dev/null \
  | tr -d ' \n' || echo "0")
echo "PLATFORM_ACCOUNTS=$PLAT"

TRG_BAL=$(sudo docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -t -c \
  "SELECT COUNT(*) FROM information_schema.triggers \
   WHERE trigger_name='ledger_balance_check'" 2>/dev/null | tr -d ' \n' || echo "0")
echo "TRIGGER_BALANCE_CHECK=$TRG_BAL"

TRG_IMM=$(sudo docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -t -c \
  "SELECT COUNT(*) FROM information_schema.triggers \
   WHERE trigger_name='cashback_plan_immutable_trg'" 2>/dev/null | tr -d ' \n' || echo "0")
echo "TRIGGER_PLAN_IMMUTABLE=$TRG_IMM"

COMM=$(sudo docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -t -c \
  "SELECT COUNT(*) FROM ref_schema.commission_rules WHERE market='TR'" 2>/dev/null \
  | tr -d ' \n' || echo "0")
echo "COMMISSION_RULES_TR=$COMM"

BIZC=$(sudo docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -t -c \
  "SELECT COUNT(*) FROM ref_schema.business_calendars WHERE market='TR'" 2>/dev/null \
  | tr -d ' \n' || echo "0")
echo "BIZ_CALENDARS_TR=$BIZC"

# ─── D: Observability ─────────────────────────────────────────────────────────
for pair in "core-svc:9100" "fin-svc:9101" "jobs-svc:9102"; do
  n="${pair%%:*}"; k="METRICS_$(echo "$n" | tr '-' '_' | tr '[:lower:]' '[:upper:]')"
  r=$(sudo docker run --rm --network mopro_mopro-net --pull never alpine \
    sh -c "wget -qO- http://${pair}/metrics 2>/dev/null | head -1 | grep -c '#' || echo 0" \
    2>/dev/null || echo "0")
  echo "${k}=$r"
done

for pair in "core-svc:8080" "fin-svc:8081" "jobs-svc:8080"; do
  n="${pair%%:*}"; k="HEALTHZ_$(echo "$n" | tr '-' '_' | tr '[:lower:]' '[:upper:]')"
  st=$(sudo docker run --rm --network mopro_mopro-net --pull never alpine \
    sh -c "wget -qS --spider http://${pair}/healthz 2>&1 | grep 'HTTP/' | awk '{print \$2}' | head -1" \
    2>/dev/null || echo "0")
  echo "${k}=${st:-0}"
done

# ─── F: Data ──────────────────────────────────────────────────────────────────
PRODS=$(sudo docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -t -c \
  "SELECT COUNT(*) FROM catalog_schema.products" 2>/dev/null | tr -d ' \n' || echo "0")
echo "PRODUCTS_COUNT=$PRODS"

SELLS=$(sudo docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -t -c \
  "SELECT COUNT(*) FROM seller_schema.sellers" 2>/dev/null | tr -d ' \n' || echo "0")
echo "SELLERS_COUNT=$SELLS"

CATS=$(sudo docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -t -c \
  "SELECT COUNT(*) FROM ref_schema.categories" 2>/dev/null | tr -d ' \n' || echo "0")
echo "CATEGORIES_COUNT=$CATS"

# ─── G: Backups ───────────────────────────────────────────────────────────────
BTIMER=$(systemctl is-active mopro-backup.timer 2>/dev/null || echo "not-found")
echo "BACKUP_TIMER_STATUS=$BTIMER"

# ─── H: Operational ───────────────────────────────────────────────────────────
DLQ=$(sudo docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -t -c \
  "SELECT COUNT(*) FROM wallet_schema.event_dlq WHERE status='open'" 2>/dev/null \
  | tr -d ' \n' || echo "0")
echo "DLQ_OPEN=$DLQ"

OB_ECOM=$(sudo docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom -t -c \
  "SELECT COUNT(*) FROM outbox WHERE published_at IS NULL" 2>/dev/null | tr -d ' \n' || echo "0")
echo "OUTBOX_LAG_ECOM=$OB_ECOM"

OB_LEDGER=$(sudo docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -t -c \
  "SELECT COUNT(*) FROM outbox WHERE published_at IS NULL" 2>/dev/null | tr -d ' \n' || echo "0")
echo "OUTBOX_LAG_LEDGER=$OB_LEDGER"

DWTIMER=$(systemctl is-active disk-watch.timer 2>/dev/null || echo "not-found")
echo "DISK_WATCH_TIMER_STATUS=$DWTIMER"

FIVEX=$(sudo docker logs caddy --since=1h 2>&1 | grep -cE ' [5][0-9]{2} ' || echo "0")
echo "FIVEX_1H=$FIVEX"

REMOTE_EOF
  ) || { echo -e "${RED}✗ SSH failed. Use --no-ssh to skip VDS checks.${NC}"; exit 1; }
  echo -e "${GREEN}✓ VDS data collected ($(printf '%s' "$VDS_CACHE" | wc -l | tr -d ' ') metrics).${NC}"
fi

# ── Source and run check sections ─────────────────────────────────────────────
if run_section A; then hdr "A — Infrastructure";  source "$CHECKS_DIR/infrastructure.sh"  && check_infrastructure; fi
if run_section B; then hdr "B — Security";        source "$CHECKS_DIR/security.sh"        && check_security;       fi
if run_section C; then hdr "C — Financial";       source "$CHECKS_DIR/financial.sh"       && check_financial;      fi
if run_section D; then hdr "D — Observability";   source "$CHECKS_DIR/observability.sh"   && check_observability;  fi
if run_section E; then hdr "E — Performance";     source "$CHECKS_DIR/performance.sh"     && check_performance;    fi
if run_section F; then hdr "F — Data";            source "$CHECKS_DIR/data.sh"            && check_data;           fi
if run_section G; then hdr "G — Backups";         source "$CHECKS_DIR/backups.sh"         && check_backups;        fi
if run_section H; then hdr "H — Operational";     source "$CHECKS_DIR/operational.sh"     && check_operational;    fi

# ── Final matrix ──────────────────────────────────────────────────────────────
ELAPSED=$(( $(date +%s) - START_TS ))
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SUMMARY  —  $(date +%Y-%m-%d\ %H:%M:%S)${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}PASS: $PASS_N${NC}   ${YELLOW}WARN: $WARN_N${NC}   ${RED}FAIL: $FAIL_N${NC}   (${ELAPSED}s)"
echo ""

if [[ $FAIL_N -eq 0 && $WARN_N -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✓ ALL CHECKS PASS — GO FOR LAUNCH${NC}"
elif [[ $FAIL_N -eq 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}⚠  No failures. Review WARNs before proceeding.${NC}"
else
  echo -e "  ${RED}${BOLD}✗ $FAIL_N FAILURE(S) — DO NOT LAUNCH${NC}"
fi
echo ""

# ── JSON output ───────────────────────────────────────────────────────────────
if [[ $JSON_OUT -eq 1 ]]; then
  JSON_FILE="$REPO_ROOT/docs/runbooks/readiness-$(date +%Y-%m-%dT%H-%M-%S).json"
  mkdir -p "$(dirname "$JSON_FILE")"
  {
    printf '{\n'
    printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "pass": %d, "warn": %d, "fail": %d,\n' "$PASS_N" "$WARN_N" "$FAIL_N"
    printf '  "elapsed_s": %d,\n' "$ELAPSED"
    printf '  "checks": [\n'
    FIRST_JSON=1
    for entry in "${RESULTS[@]}"; do
      IFS='|' read -r jstatus jsec jchk jdetail <<< "$entry"
      [[ $FIRST_JSON -eq 0 ]] && printf ',\n'
      printf '    {"status":"%s","section":"%s","check":"%s","detail":"%s"}' \
        "$jstatus" "$jsec" "${jchk//\"/\\\"}" "${jdetail//\"/\\\"}"
      FIRST_JSON=0
    done
    printf '\n  ]\n}\n'
  } > "$JSON_FILE"
  echo -e "  JSON → $JSON_FILE"
fi

# ── Exit ──────────────────────────────────────────────────────────────────────
[[ $FAIL_N -eq 0 ]]
