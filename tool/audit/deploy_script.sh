#!/usr/bin/env bash
# tool/audit/deploy_script.sh
# Consolidated deploy + verify + photo-upload-gate script for the Mopro deploy host.
# Run on the deploy host with sudo. Paste the ENTIRE stdout back to Claude Code.
#
# This stack is distroless (no shell/nc/wget/curl/env inside the service images)
# and the services publish NO host ports — only Caddy exposes :80. So health/SHA
# checks go through Caddy on localhost:80, and env is read via `docker inspect`
# (the container config), never via `docker compose exec ... env`.

# Fail-fast (F-DH-1 §3.1): any unhandled failure aborts the deploy with a
# non-zero exit — a denied pull or failed login can never scroll past into a
# green run again. Lines that may legitimately fail carry explicit handlers.
set -euo pipefail

OUT_DIR="/tmp/deploy_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR"
exec > >(tee "$OUT_DIR/full_output.log") 2>&1

SERVICES="core-svc fin-svc jobs-svc"

# F-DH-1 §3.3: image namespace + tag, passed into compose interpolation through
# sudo on every dc() call. Default matches what build-images.yml actually
# pushes (owner-relative: ghcr.io/s4l1hs/* today). GHCR requires lowercase.
IMAGE_NS="$(printf '%s' "${IMAGE_NS:-s4l1hs}" | tr '[:upper:]' '[:lower:]')"
VERSION="${VERSION:-latest}"

# VERIFY_ONLY=true → exercise SSH/scp/discovery/compose-config WITHOUT pull/up or the
#   photo-upload POST. Non-destructive; used to smoke-test the deploy workflow.
# SKIP_PHOTO_SMOKE=true → skip only STEP 8 (when host test creds aren't provisioned).
VERIFY_ONLY="${VERIFY_ONLY:-false}"
SKIP_PHOTO_SMOKE="${SKIP_PHOTO_SMOKE:-false}"
echo "MODE: VERIFY_ONLY=$VERIFY_ONLY  SKIP_PHOTO_SMOKE=$SKIP_PHOTO_SMOKE"
echo

# ── Compose directory discovery ─────────────────────────────────────────────────
# F-DH-1 §3.2: the PRODUCTION compose file is required and targeted explicitly
# with -f on every invocation. A bare `docker compose` auto-loads the DEV
# docker-compose.yml (same project name!) — that's defect ① of the #104 no-op
# deploy. deploy.yml scps a fresh docker-compose.prod.yml here each run.
# Override:  COMPOSE_DIR=/path bash deploy_script.sh
# Else tries: /opt/mopro/deploy → /opt/mopro → find / (maxdepth 4).
has_compose() { [ -f "$1/docker-compose.prod.yml" ]; }
if [ -n "${COMPOSE_DIR:-}" ]; then
  has_compose "$COMPOSE_DIR" || { echo "FATAL: COMPOSE_DIR=$COMPOSE_DIR has no docker-compose.prod.yml"; exit 1; }
  echo "Using COMPOSE_DIR=$COMPOSE_DIR (env override)"
elif has_compose /opt/mopro/deploy; then
  COMPOSE_DIR=/opt/mopro/deploy; echo "Discovered: $COMPOSE_DIR"
elif has_compose /opt/mopro; then
  COMPOSE_DIR=/opt/mopro; echo "Discovered: $COMPOSE_DIR"
else
  echo "Compose file not in known locations; searching (find, maxdepth 4)..."
  FOUND=$(find / -maxdepth 4 -name 'docker-compose.prod.yml' \
    -not -path '*/proc/*' -not -path '*/sys/*' -not -path '*/.git/*' 2>/dev/null | head -1)
  [ -n "$FOUND" ] || { echo "FATAL: no docker-compose.prod.yml found anywhere on host"; exit 1; }
  COMPOSE_DIR=$(dirname "$FOUND"); echo "Discovered (via find): $COMPOSE_DIR"
fi
cd "$COMPOSE_DIR" || { echo "FATAL: cd $COMPOSE_DIR failed"; exit 1; }
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.prod.yml"
echo "Working directory: $(pwd)"
echo "Compose file:      $COMPOSE_FILE"
echo
dc() { sudo IMAGE_NS="$IMAGE_NS" VERSION="$VERSION" docker compose -f "$COMPOSE_FILE" "$@"; }

echo "===== STEP 0: PRE-DEPLOY STATE ====="
dc ps
echo
dc images $SERVICES
echo
echo "--- pre-deploy core-svc /__version (current SHA before rollout) ---"
curl -fsS -m 5 http://localhost/__version || echo "(unreachable — service may be down pre-deploy)"
echo; echo

echo "===== STEP 1: IMAGE REFS (IMAGE_NS=${IMAGE_NS} VERSION=${VERSION}) ====="
# F-DH-1 §3.3: namespace/tag flow ONLY through dc()'s env passthrough — the old
# append-to-.env hack is gone (it mutated the root-only secrets file via a
# broken unprivileged existence check, and was inert against the stale host
# dev compose anyway: #104 F-DH-6).
echo "--- resolved image refs (docker compose config) ---"
dc config 2>/dev/null | grep -E 'image: ghcr' | sort -u \
  || { echo "FATAL: compose config resolved no ghcr image refs — check $COMPOSE_FILE" >&2; exit 1; }
echo

if [ "$VERIFY_ONLY" = "true" ]; then
  echo "===== STEP 2-3: SKIPPED (VERIFY_ONLY=true — no pull/up; plumbing-only run) ====="
  echo
else
echo "===== STEP 2: DOCKER COMPOSE PULL ====="
if ! dc pull $SERVICES; then
  echo "FATAL: docker compose pull failed — NOTHING was deployed." >&2
  echo "       Check GHCR login (STEP 1.5) and that the image refs above exist." >&2
  exit 1
fi
echo

echo "===== STEP 3: DOCKER COMPOSE UP ====="
dc up -d $SERVICES
sleep 15
echo
fi

echo "===== STEP 4: POST-DEPLOY STATE ====="
dc ps
echo
dc images $SERVICES
echo

echo "===== STEP 5: HEALTH + DEPLOYED SHA (via Caddy on :80; distroless-safe) ====="
echo "--- Caddy native /healthz (ingress up?) ---"
curl -fsS -m 5 http://localhost/healthz || echo "CADDY HEALTHZ FAILED"
echo
echo "--- core-svc /__version ---"
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
if [ "$VERIFY_ONLY" = "true" ]; then
  echo "SKIPPED — VERIFY_ONLY=true (the upload POST is a write; not run in plumbing-only mode)."
elif [ "$SKIP_PHOTO_SMOKE" = "true" ]; then
  echo "SKIPPED via SKIP_PHOTO_SMOKE=true."
elif [ -f /root/.deploy_test_creds ]; then
  # shellcheck disable=SC1091
  . /root/.deploy_test_creds
  TOKEN=$(curl -sS -m 10 -X POST http://localhost/auth/login \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${TEST_EMAIL:-}\",\"password\":\"${TEST_PASSWORD:-}\"}" \
    | jq -r '.access_token // .token // empty' 2>/dev/null || true)
  if [ -z "$TOKEN" ]; then
    echo "Could not obtain test auth token — login failed (check creds / /auth/login path)."
  else
    curl -sS -m 10 https://placehold.co/600x400/png -o /tmp/test_upload.png 2>/dev/null \
      || { head -c 2048 /dev/urandom > /tmp/test_upload.png; echo "(placehold unreachable; sent random bytes — may fail image validation)"; }
    echo "--- POST /uploads/photos response (headers + body) ---"
    curl -sS -m 15 -i -X POST http://localhost/uploads/photos \
      -H "Authorization: Bearer $TOKEN" \
      -F "file=@/tmp/test_upload.png;type=image/png" \
      -F "entity_type=review" 2>&1 | head -40 || true
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
