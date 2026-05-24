#!/usr/bin/env bash
# run.sh — convenience wrapper for running load test profiles.
# Usage: ./run.sh <profile> [k6-extra-args...]
#   profile: smoke | baseline | stress | spike | soak
#   e.g.   : ./run.sh baseline
#          : ./run.sh smoke --no-color
#
# ⚠️  WARN SALIH before running stress or spike against production.
set -euo pipefail

LOAD_TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${1:-smoke}"
shift || true  # remaining args passed to k6

BASE_URL="${BASE_URL:-https://api.moproshop.com}"
SSH_HOST="${VDS_SSH_HOST:-mopro@195.85.207.92}"
SSH_PORT="${VDS_SSH_PORT:-4625}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
hdr()  { echo -e "\n${BOLD}=== $* ===${NC}"; }

# ── Validate profile ──────────────────────────────────────────────────────────
case "$PROFILE" in
  smoke|baseline|stress|spike|soak) ;;
  *)
    fail "Unknown profile '$PROFILE'. Valid: smoke baseline stress spike soak"
    exit 1
    ;;
esac

# ── Safety gate for destructive profiles ─────────────────────────────────────
if [[ "$PROFILE" == "stress" || "$PROFILE" == "spike" ]]; then
  warn "Profile '$PROFILE' will send high load to $BASE_URL."
  warn "Confirm this is pre-launch (no real users). Ctrl+C to cancel."
  read -r -p "Type 'yes' to continue: " confirm
  [[ "$confirm" == "yes" ]] || { fail "Aborted."; exit 1; }
fi

# ── Check prerequisites ───────────────────────────────────────────────────────
hdr "Prerequisites"

if ! command -v k6 &>/dev/null; then
  fail "k6 not found. Install: brew install k6  OR  docker run grafana/k6"
  exit 1
fi
ok "k6 $(k6 version | head -1)"

# ── Ensure tokens exist ───────────────────────────────────────────────────────
hdr "Token check"
TOKENS_FILE="$LOAD_TESTS_DIR/.tokens.json"
REFRESH_FILE="$LOAD_TESTS_DIR/.refresh.json"

if [[ ! -f "$TOKENS_FILE" ]]; then
  warn ".tokens.json not found — running setup.sh..."
  bash "$LOAD_TESTS_DIR/setup.sh"
else
  count=$(python3 -c "import json; d=json.load(open('$TOKENS_FILE')); print(len(d))" 2>/dev/null || echo 0)
  ok "$count tokens found in .tokens.json"
fi

# ── Refresh access tokens (15-min JWT TTL — always refresh before running) ───
hdr "Refreshing access tokens"
if [[ -f "$REFRESH_FILE" ]]; then
python3 - <<PYEOF
import json, urllib.request, urllib.error, sys, os

tf  = '$TOKENS_FILE'
rf  = '$REFRESH_FILE'
url = '$BASE_URL/auth/token/refresh'

refreshes = json.load(open(rf))
tokens    = json.load(open(tf)) if os.path.exists(tf) else {}

new_tokens    = {}
new_refreshes = {}
ok_n = 0; fail_n = 0; revoked_n = 0

for phone, rt in refreshes.items():
    req = urllib.request.Request(
        url,
        data=json.dumps({'refresh_token': rt}).encode(),
        headers={'Content-Type': 'application/json'},
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.load(resp)
        at     = data.get('access_token', '')
        new_rt = data.get('refresh_token', rt)
        if at:
            new_tokens[phone]    = at
            new_refreshes[phone] = new_rt
            ok_n += 1
        else:
            fail_n += 1
            print(f'  ! {phone}: no access_token in response', flush=True)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        if 'revoked' in body:
            revoked_n += 1
        else:
            fail_n += 1
            print(f'  ! {phone} HTTP {e.code}: {body[:60]}', flush=True)

if new_tokens:
    json.dump(new_tokens,    open(tf, 'w'), indent=2)
    json.dump(new_refreshes, open(rf, 'w'), indent=2)
    print(f'Refreshed {ok_n} tokens ({revoked_n} revoked, {fail_n} failed). {len(new_tokens)} ready.', flush=True)
else:
    print('No tokens refreshed — tokens may be expired. Re-run setup.sh.', flush=True)
    sys.exit(1)
PYEOF
  if [[ $? -ne 0 ]]; then
    fail "Token refresh failed. Run: FORCE_REPROVISION=1 bash setup.sh"
    exit 1
  fi
  ok "Access tokens refreshed"
else
  warn ".refresh.json not found — tokens may expire mid-test. Run setup.sh."
fi

# ── Refresh OTPs for S2 (otp-verify scenario) ────────────────────────────────
hdr "Refreshing OTPs for S2 (otp-verify)"
OTPS_FILE="$LOAD_TESTS_DIR/.otps.json"

echo '[]' > "$OTPS_FILE"  # default: empty → S2 falls back to /me

otp_refreshed=0
otp_failed=0

# Request fresh OTPs for first 20 users (enough for S2 VU pool in all profiles).
for i in $(seq 0 19); do
  phone="+9055500$(printf '%05d' $i)"

  http_code=$(curl -s \
    -X POST "$BASE_URL/auth/otp/request" \
    -H "Content-Type: application/json" \
    -d "{\"phone\":\"$phone\",\"purpose\":\"login\"}" \
    -w "%{http_code}" -o /dev/null 2>/dev/null || echo "000")

  if [[ "$http_code" != "204" ]]; then
    ((otp_failed++)) || true
    continue
  fi

  sleep 0.3

  log_line=$(ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o BatchMode=yes \
    -o ConnectTimeout=5 "$SSH_HOST" \
    "sudo docker logs core-svc 2>&1 | grep 'mock SMS: OTP code' | grep '\"to\":\"${phone}\"' | tail -1" \
    2>/dev/null || true)

  code=$(echo "$log_line" | grep -o '"code":"[^"]*"' | cut -d'"' -f4 || true)
  [[ -z "$code" ]] && { ((otp_failed++)) || true; continue; }

  # Append to otps array
  python3 - <<PYEOF
import json, os
f = '$OTPS_FILE'
data = json.load(open(f)) if os.path.exists(f) else []
data.append({"phone": "$phone", "code": "$code"})
json.dump(data, open(f, 'w'), indent=2)
PYEOF
  ((otp_refreshed++)) || true
done

ok "$otp_refreshed fresh OTPs written to $OTPS_FILE ($otp_failed failed)"

# ── Determine output paths ────────────────────────────────────────────────────
hdr "Running k6 — profile: $PROFILE"
TS=$(date +%Y-%m-%dT%H-%M-%S)
SUMMARY_JSON="$LOAD_TESTS_DIR/reports/${PROFILE}-${TS}.json"
mkdir -p "$LOAD_TESTS_DIR/reports"

# ── Run k6 ───────────────────────────────────────────────────────────────────
cd "$LOAD_TESTS_DIR"

set +e  # don't exit on k6 non-zero (threshold failures are expected in stress)
K6_PROFILE="$PROFILE" k6 run \
  --env BASE_URL="$BASE_URL" \
  --env K6_PROFILE="$PROFILE" \
  --summary-export="$SUMMARY_JSON" \
  "$@" \
  "profiles/${PROFILE}.js"
k6_exit=$?
set -e

echo ""
hdr "Post-run"

# ── Capture VDS stats ─────────────────────────────────────────────────────────
echo "VDS container stats at end of test:"
ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o BatchMode=yes \
  -o ConnectTimeout=5 "$SSH_HOST" \
  'sudo docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"' \
  2>/dev/null || warn "Could not fetch VDS stats (SSH unavailable)"

echo ""
if [[ -f "$SUMMARY_JSON" ]]; then
  ok "Summary JSON → $SUMMARY_JSON"
fi

# Find the generated markdown report
MD_REPORT=$(ls -1t "$LOAD_TESTS_DIR/reports/${PROFILE}-"*.md 2>/dev/null | head -1 || true)
if [[ -n "$MD_REPORT" ]]; then
  ok "Markdown report → $MD_REPORT"
  echo ""
  echo "--- Report preview (first 40 lines) ---"
  head -40 "$MD_REPORT"
fi

echo ""
if [[ $k6_exit -eq 0 ]]; then
  ok "All SLO thresholds passed. ✅"
else
  warn "k6 exited $k6_exit — some thresholds failed. Review the report above."
fi

exit $k6_exit
