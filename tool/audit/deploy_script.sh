#!/usr/bin/env bash
# tool/audit/deploy_script.sh
# Consolidated deploy + verify + photo-upload-gate script for the Mopro deploy host.
# Run on the deploy host with sudo. Paste the ENTIRE stdout back to Claude Code.
#
# This stack is distroless (no shell/nc/wget/curl/env inside the service images)
# and the services publish NO host ports — only Caddy exposes :80. So health/SHA
# checks go through Caddy on localhost:80, and env is read via `docker inspect`
# (the container config), never via `docker compose exec ... env`.

set -u
set -o pipefail

OUT_DIR="/tmp/deploy_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"
exec > >(tee "$OUT_DIR/full_output.log") 2>&1

COMPOSE_DIR="/opt/mopro"
SERVICES="core-svc fin-svc jobs-svc"
EXPECTED_SHA_PREFIX="7b8d96cc"   # PR #49 = last backend build; :latest points here

cd "$COMPOSE_DIR" || { echo "FATAL: $COMPOSE_DIR missing"; exit 1; }
dc() { sudo docker compose "$@"; }

echo "===== STEP 0: PRE-DEPLOY STATE ====="
dc ps
echo
dc images $SERVICES
echo
echo "--- pre-deploy core-svc /__version (current SHA before rollout) ---"
curl -fsS -m 5 http://localhost/__version || echo "(unreachable — service may be down pre-deploy)"
echo; echo

echo "===== STEP 1: SET IMAGE_NS ====="
if grep -q '^IMAGE_NS=' "$COMPOSE_DIR/.env" 2>/dev/null; then
  echo "Already set: $(grep '^IMAGE_NS=' "$COMPOSE_DIR/.env" | head -1)"
else
  echo 'IMAGE_NS=s4l1hs' | sudo tee -a "$COMPOSE_DIR/.env" > /dev/null
  echo "Set: IMAGE_NS=s4l1hs"
fi
echo

echo "===== STEP 2: DOCKER COMPOSE PULL ====="
dc pull $SERVICES
echo

echo "===== STEP 3: DOCKER COMPOSE UP ====="
dc up -d $SERVICES
sleep 15
echo

echo "===== STEP 4: POST-DEPLOY STATE ====="
dc ps
echo
dc images $SERVICES
echo

echo "===== STEP 5: HEALTH + DEPLOYED SHA (via Caddy on :80; distroless-safe) ====="
echo "--- Caddy native /healthz (ingress up?) ---"
curl -fsS -m 5 http://localhost/healthz || echo "CADDY HEALTHZ FAILED"
echo
echo "--- core-svc /__version (expect sha prefix ${EXPECTED_SHA_PREFIX}) ---"
curl -fsS -m 5 http://localhost/__version || echo "CORE-SVC /__version UNREACHABLE"
echo
echo "(fin-svc/jobs-svc have no host-reachable health route through Caddy — judged"
echo " by State=Up in STEP 4 + absence of panics in STEP 6; both build from the same"
echo " workflow run as core-svc.)"
echo

echo "===== STEP 6: STARTUP LOGS (errors only, last 80 lines) ====="
for svc in $SERVICES; do
  echo "--- $svc ---"
  dc logs --tail 80 "$svc" 2>&1 | grep -iE 'error|fatal|panic' | head -10 || true
  echo "(end $svc; empty above = clean)"
  echo
done

echo "===== STEP 7: STORAGE ENV (photo-upload gate prereq; via docker inspect) ====="
CID=$(dc ps -q core-svc)
if [ -z "$CID" ]; then
  echo "core-svc container not found — cannot read env."
else
  sudo docker inspect "$CID" --format '{{range .Config.Env}}{{println .}}{{end}}' \
    | grep -E '^(STORAGE|CDN_BASE_URL)=' | sort \
    || echo "NO STORAGE_* / CDN_BASE_URL vars present in core-svc config."
fi
echo

echo "===== STEP 8: PHOTO UPLOAD SMOKE TEST ====="
# Requires test creds in /root/.deploy_test_creds:  TEST_EMAIL=... / TEST_PASSWORD=...
if [ -f /root/.deploy_test_creds ]; then
  # shellcheck disable=SC1091
  . /root/.deploy_test_creds
  TOKEN=$(curl -sS -m 10 -X POST http://localhost/auth/login \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${TEST_EMAIL:-}\",\"password\":\"${TEST_PASSWORD:-}\"}" \
    | jq -r '.access_token // .token // empty' 2>/dev/null)
  if [ -z "$TOKEN" ]; then
    echo "Could not obtain test auth token — login failed (check creds / /auth/login path)."
  else
    curl -sS -m 10 https://placehold.co/600x400/png -o /tmp/test_upload.png 2>/dev/null \
      || { head -c 2048 /dev/urandom > /tmp/test_upload.png; echo "(placehold unreachable; sent random bytes — may fail image validation)"; }
    echo "--- POST /uploads/photos response (headers + body) ---"
    curl -sS -m 15 -i -X POST http://localhost/uploads/photos \
      -H "Authorization: Bearer $TOKEN" \
      -F "file=@/tmp/test_upload.png;type=image/png" \
      -F "entity_type=review" 2>&1 | head -40
    rm -f /tmp/test_upload.png
  fi
else
  echo "SKIPPED — /root/.deploy_test_creds not found."
  echo "To run: sudo tee /root/.deploy_test_creds <<EOF"
  echo "TEST_EMAIL=<test_user_email>"
  echo "TEST_PASSWORD=<test_user_password>"
  echo "EOF"
  echo "sudo chmod 600 /root/.deploy_test_creds   # then re-run this script"
fi
echo

echo "===== END ====="
echo "Full output captured at: $OUT_DIR/full_output.log"
echo "Paste the entire output above back to Claude Code."
