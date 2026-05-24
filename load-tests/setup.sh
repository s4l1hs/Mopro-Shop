#!/usr/bin/env bash
# setup.sh — provision 100 test users + 1 address each.
# Idempotent: if .tokens.json already contains valid tokens, skips re-provisioning.
# Writes: .tokens.json  (access tokens — gitignored)
#         .refresh.json (refresh tokens — gitignored, for future token refresh tests)
set -euo pipefail

LOAD_TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_URL="${BASE_URL:-https://api.moproshop.com}"
TOKENS_FILE="$LOAD_TESTS_DIR/.tokens.json"
REFRESH_FILE="$LOAD_TESTS_DIR/.refresh.json"
SSH_HOST="${VDS_SSH_HOST:-mopro@195.85.207.92}"
SSH_PORT="${VDS_SSH_PORT:-4625}"
COUNT=100

# Colour helpers
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }

echo "======================================"
echo " Mopro Load Test Setup"
echo " Target : $BASE_URL"
echo " SSH    : $SSH_HOST:$SSH_PORT"
echo " Users  : $COUNT"
echo "======================================"
echo ""

# ── Check prerequisites ───────────────────────────────────────────────────────
if ! command -v curl &>/dev/null; then
  fail "curl is required but not found"
  exit 1
fi

# Test SSH connectivity
if ! ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
     -o BatchMode=yes "$SSH_HOST" 'echo ok' &>/dev/null 2>&1; then
  warn "SSH to VDS not available — OTP code extraction will fail."
  warn "Set VDS_SSH_HOST / VDS_SSH_PORT env vars if the defaults are wrong."
fi

# ── Check if tokens already valid ────────────────────────────────────────────
if [[ -f "$TOKENS_FILE" ]]; then
  existing=$(python3 -c "import json; d=json.load(open('$TOKENS_FILE')); print(len(d))" 2>/dev/null || echo 0)
  if [[ "$existing" -ge "$COUNT" ]]; then
    # Spot-check first token
    first_phone=$(python3 -c "import json; d=json.load(open('$TOKENS_FILE')); print(list(d.keys())[0])" 2>/dev/null || echo "")
    first_token=$(python3 -c "import json; d=json.load(open('$TOKENS_FILE')); print(list(d.values())[0])" 2>/dev/null || echo "")
    if [[ -n "$first_token" ]]; then
      http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $first_token" \
        "$BASE_URL/me" 2>/dev/null || echo "000")
      if [[ "$http_code" == "200" ]]; then
        ok "Tokens valid ($existing users in $TOKENS_FILE). Skipping re-provisioning."
        ok "Run with FORCE_REPROVISION=1 to force a fresh setup."
        exit 0
      else
        warn "Existing tokens appear expired (HTTP $http_code). Re-provisioning..."
      fi
    fi
  fi
fi

if [[ "${FORCE_REPROVISION:-0}" != "1" ]] && [[ -f "$TOKENS_FILE" ]]; then
  : # already handled above
fi

# ── Provision users ───────────────────────────────────────────────────────────
declare -A TOKENS
declare -A REFRESH_TOKENS

provisioned=0
failed=0

for i in $(seq 0 $((COUNT-1))); do
  phone="+9055500$(printf '%05d' $i)"

  # ── 1. OTP request ──────────────────────────────────────────────────────────
  # NOTE: use -s (silent) but NOT -f (fail) so curl still outputs the HTTP code
  # for 4xx responses without the error code being swallowed.
  http_code=$(curl -s \
    -X POST "$BASE_URL/auth/otp/request" \
    -H "Content-Type: application/json" \
    -d "{\"phone\":\"$phone\",\"purpose\":\"login\"}" \
    -w "%{http_code}" -o /dev/null 2>/dev/null || echo "000")

  if [[ "$http_code" == "429" ]]; then
    warn "[$((i+1))/$COUNT] $phone → IP rate limit (10/hr). Waiting ${BATCH_WAIT_SECONDS:-3600}s..."
    sleep "${BATCH_WAIT_SECONDS:-3600}"
    # Retry once after waiting
    http_code=$(curl -s \
      -X POST "$BASE_URL/auth/otp/request" \
      -H "Content-Type: application/json" \
      -d "{\"phone\":\"$phone\",\"purpose\":\"login\"}" \
      -w "%{http_code}" -o /dev/null 2>/dev/null || echo "000")
  fi

  if [[ "$http_code" != "204" ]]; then
    fail "[$((i+1))/$COUNT] $phone OTP request → HTTP $http_code"
    ((failed++)) || true
    continue
  fi

  sleep 0.3  # give core-svc time to write the log line

  # ── 2. Extract OTP code from docker logs ────────────────────────────────────
  log_line=$(ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no \
    -o BatchMode=yes -o ConnectTimeout=5 "$SSH_HOST" \
    "sudo docker logs core-svc 2>&1 | grep 'mock SMS: OTP code' | grep '\"to\":\"${phone}\"' | tail -1" \
    2>/dev/null || true)

  code=$(echo "$log_line" | grep -o '"code":"[^"]*"' | cut -d'"' -f4 || true)

  if [[ -z "$code" ]]; then
    fail "[$((i+1))/$COUNT] $phone → could not extract OTP code from docker logs"
    ((failed++)) || true
    continue
  fi

  # ── 3. OTP verify ───────────────────────────────────────────────────────────
  resp=$(curl -s \
    -X POST "$BASE_URL/auth/otp/verify" \
    -H "Content-Type: application/json" \
    -H "Idempotency-Key: setup-verify-$(printf '%05d' $i)-$$" \
    -d "{\"phone\":\"$phone\",\"code\":\"$code\",\"purpose\":\"login\"}" \
    2>/dev/null || echo '{}')

  access_token=$(echo "$resp"  | grep -o '"access_token":"[^"]*"'  | cut -d'"' -f4 || true)
  refresh_token=$(echo "$resp" | grep -o '"refresh_token":"[^"]*"' | cut -d'"' -f4 || true)

  if [[ -z "$access_token" ]]; then
    fail "[$((i+1))/$COUNT] $phone → OTP verify failed (code=$code)"
    ((failed++)) || true
    continue
  fi

  TOKENS[$phone]="$access_token"
  [[ -n "$refresh_token" ]] && REFRESH_TOKENS[$phone]="$refresh_token" || true

  # ── 4. Create test address ───────────────────────────────────────────────────
  addr_body="{\"label\":\"Load Test\",\"name\":\"Test Kullanici\",\"phone\":\"$phone\",\"full_address\":\"Test Cad. No:1\",\"city\":\"Istanbul\",\"district\":\"Kadikoy\",\"postal_code\":\"34710\"}"
  addr_code=$(curl -s \
    -X POST "$BASE_URL/addresses" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $access_token" \
    -H "Idempotency-Key: setup-addr-$(printf '%05d' $i)-$$" \
    -d "$addr_body" \
    -w "%{http_code}" -o /dev/null 2>/dev/null || echo "000")

  addr_ok=""
  if [[ "$addr_code" == "201" || "$addr_code" == "200" || "$addr_code" == "409" ]]; then
    addr_ok=" + address"
  fi

  ok "[$((i+1))/$COUNT] $phone ✓${addr_ok}"
  ((provisioned++)) || true

  # Rate-limit politeness: 100ms between consecutive new accounts.
  sleep 0.1
done

echo ""
echo "======================================"
echo " Results: $provisioned provisioned, $failed failed"
echo "======================================"

if [[ "$provisioned" -eq 0 ]]; then
  fail "No users provisioned. Aborting."
  exit 1
fi

# ── Write .tokens.json ────────────────────────────────────────────────────────
python3 - <<PYEOF
import json, sys
tokens = {}
$(for phone in "${!TOKENS[@]}"; do echo "tokens['$phone'] = '${TOKENS[$phone]}'"; done)
with open('$TOKENS_FILE', 'w') as f:
    json.dump(tokens, f, indent=2)
print(f"Wrote {len(tokens)} tokens to $TOKENS_FILE")
PYEOF

# ── Write .refresh.json ───────────────────────────────────────────────────────
python3 - <<PYEOF
import json
refreshes = {}
$(for phone in "${!REFRESH_TOKENS[@]}"; do echo "refreshes['$phone'] = '${REFRESH_TOKENS[$phone]}'"; done)
with open('$REFRESH_FILE', 'w') as f:
    json.dump(refreshes, f, indent=2)
PYEOF

echo ""
ok "Setup complete. $provisioned test users ready."
ok "Tokens → $TOKENS_FILE"
ok "Run the load test: ./run.sh smoke"
