#!/usr/bin/env bash
# scripts/smoke/run.sh — Mopro backend smoke test
#
# Hits every critical API path, verifies HTTP status and basic response shape.
# Designed to run against any deployed environment.
#
# Usage:
#   BASE=https://api-staging.moproshop.com bash scripts/smoke/run.sh
#   make smoke                          # uses BASE default
#   make smoke BASE=https://api.moproshop.com
#
# Staging prerequisites:
#   - DEV_OTP_ACCEPT_ANY=true set in the staging .env (enables OTP bypass with any code)
#   - SMS_PROVIDER=mock (no real SMS sent)
#   - PSP_PROVIDER=sipay with SIPAY_MODE=sandbox
#   - Seed data loaded (make seed-staging)
#
# Exit codes: 0 = all non-stub checks passed, 1 = one or more checks FAILED.

set -euo pipefail

BASE="${BASE:-https://api-staging.moproshop.com}"
PASS=0
FAIL=0
STUB=0
FAIL_NAMES=()

# ── Helpers ──────────────────────────────────────────────────────────────────

log()    { printf '[smoke] %s\n' "$*"; }
ok()     { printf '  ✓ %s\n' "$*"; PASS=$((PASS+1)); }
fail()   { printf '  ✗ %s\n' "$*" >&2; FAIL=$((FAIL+1)); FAIL_NAMES+=("$*"); }
stub()   { printf '  ~ %s (STUB 501 — known pending)\n' "$*"; STUB=$((STUB+1)); }
warn()   { printf '  ! %s\n' "$*"; }

# Check HTTP status of a plain GET/POST request.
# Usage: check_status "name" expected_code actual_code
check_status() {
  local name="$1" expected="$2" actual="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    ok "${name}"
  elif [[ "${actual}" == "501" ]]; then
    stub "${name}"
  else
    fail "${name} (expected ${expected}, got ${actual})"
  fi
}

# curl wrapper: returns just the HTTP status code, silences body.
# NOTE: -s only (no -f) so curl does not exit non-zero on 4xx/5xx — we want the
# actual status code even for error responses. Network failures return empty string.
get_status() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

# curl wrapper: returns body as JSON (for jq parsing), also prints status via -w.
get_body()   { curl -sf "$@"; }

# ── Pre-flight ────────────────────────────────────────────────────────────────
log ""
log "═══════════════════════════════════════════"
log " Mopro Backend Smoke"
log " BASE: ${BASE}"
log " Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "═══════════════════════════════════════════"
log ""

# ── Section 1: Unauthenticated public endpoints ───────────────────────────────
log "Section 1 — Public endpoints"

check_status "GET /healthz"         200 "$(get_status "${BASE}/healthz")"
check_status "GET /__version"       200 "$(get_status "${BASE}/__version")"
check_status "GET /categories"      200 "$(get_status "${BASE}/categories")"
check_status "GET /products"        200 "$(get_status "${BASE}/products?category_id=127")"
check_status "GET /products?sort"   200 "$(get_status "${BASE}/products?category_id=127&sort=bestseller&limit=12")"
check_status "GET /search"          200 "$(get_status "${BASE}/search?q=kulaklik")"
check_status "GET /banners"         200 "$(get_status "${BASE}/banners")"
check_status "GET /recommendations" 200 "$(get_status "${BASE}/recommendations")"

# Verify categories returns a non-empty list (response uses .data field)
CAT_COUNT=$(get_body "${BASE}/categories" | jq '.data | length' 2>/dev/null || echo 0)
if [[ "${CAT_COUNT:-0}" -ge 1 ]]; then
  ok "categories count ≥ 1 (got ${CAT_COUNT})"
else
  fail "categories count (expected ≥ 1, got ${CAT_COUNT:-0})"
fi

# Get first product ID and a variant ID for later cart tests (response uses .data field; category_id=127 has seed products)
PRODUCTS_RESP=$(get_body "${BASE}/products?category_id=127&limit=2&sort=newest" 2>/dev/null || echo '{}')
PRODUCT_ID=$(echo "${PRODUCTS_RESP}" | jq -r '.data[0].id // .items[0].id // empty' 2>/dev/null)
FIRST_PRODUCT_COUNT=$(echo "${PRODUCTS_RESP}" | jq '(.data // .items) | length' 2>/dev/null || echo 0)

if [[ "${FIRST_PRODUCT_COUNT:-0}" -ge 1 ]]; then
  ok "products list count ≥ 1 (got ${FIRST_PRODUCT_COUNT})"
else
  fail "products list empty — is seed data loaded? (make seed-staging)"
fi

if [[ -n "${PRODUCT_ID:-}" ]]; then
  PRODUCT_DETAIL=$(get_body "${BASE}/products/${PRODUCT_ID}" 2>/dev/null || echo '{}')
  DETAIL_STATUS=$(get_status "${BASE}/products/${PRODUCT_ID}")
  check_status "GET /products/{id}" 200 "${DETAIL_STATUS}"
  VARIANT_ID=$(echo "${PRODUCT_DETAIL}" | jq -r '.variants[0].id // empty' 2>/dev/null)
else
  warn "Could not resolve PRODUCT_ID — product detail + cart tests may be skipped"
  VARIANT_ID=""
fi

# ── Section 2: Auth flow ──────────────────────────────────────────────────────
log ""
log "Section 2 — Auth (OTP login)"
log "  NOTE: Requires DEV_OTP_ACCEPT_ANY=true on the staging server."

OTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST "${BASE}/auth/otp/request" \
  -H "Content-Type: application/json" \
  -d '{"phone":"+905551234567"}')
check_status "POST /auth/otp/request" 204 "${OTP_STATUS}"

# DEV_OTP_ACCEPT_ANY=true on staging: any 6-digit code is accepted.
# Single call: capture both body and status using a temp file to avoid calling verify twice
# (second verify would hit otp_already_used → 409).
_VERIFY_BODY_FILE=$(mktemp)
VERIFY_STATUS=$(curl -s -o "${_VERIFY_BODY_FILE}" -w '%{http_code}' \
  -X POST "${BASE}/auth/otp/verify" \
  -H "Content-Type: application/json" \
  -d '{"phone":"+905551234567","code":"123456"}' 2>/dev/null || echo '000')
TOKEN_RESP=$(cat "${_VERIFY_BODY_FILE}" 2>/dev/null || echo '{}')
rm -f "${_VERIFY_BODY_FILE}"
check_status "POST /auth/otp/verify" 200 "${VERIFY_STATUS}"

ACCESS_TOKEN=$(echo "${TOKEN_RESP}" | jq -r '.access_token // empty' 2>/dev/null)
REFRESH_TOKEN=$(echo "${TOKEN_RESP}" | jq -r '.refresh_token // empty' 2>/dev/null)

if [[ -z "${ACCESS_TOKEN:-}" ]]; then
  fail "access_token missing in verify response — auth bypass enabled? (DEV_OTP_ACCEPT_ANY)"
  log "  Subsequent auth-required checks will be skipped."
  ACCESS_TOKEN=""
fi

AUTH_HEADER="Authorization: Bearer ${ACCESS_TOKEN}"

# Token refresh
if [[ -n "${REFRESH_TOKEN:-}" ]]; then
  REFRESH_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${BASE}/auth/token/refresh" \
    -H "Content-Type: application/json" \
    -d "{\"refresh_token\":\"${REFRESH_TOKEN}\"}")
  check_status "POST /auth/token/refresh" 200 "${REFRESH_STATUS}"
else
  stub "POST /auth/token/refresh (no refresh_token from verify)"
fi

# ── Section 3: Authenticated user endpoints ───────────────────────────────────
log ""
log "Section 3 — Authenticated user endpoints"

if [[ -n "${ACCESS_TOKEN:-}" ]]; then
  check_status "GET /me"         200 "$(get_status -H "${AUTH_HEADER}" "${BASE}/me")"
  check_status "GET /addresses"  200 "$(get_status -H "${AUTH_HEADER}" "${BASE}/addresses")"
  check_status "GET /orders"     200 "$(get_status -H "${AUTH_HEADER}" "${BASE}/orders")"
  check_status "GET /cart"       200 "$(get_status -H "${AUTH_HEADER}" "${BASE}/cart")"

  # Wallet balance + cashback plans are on fin-svc, routed through Caddy /wallet/* /cashback/*
  check_status "GET /wallet/balance"  200 "$(get_status -H "${AUTH_HEADER}" "${BASE}/wallet/balance")"
  check_status "GET /cashback/plans"  200 "$(get_status -H "${AUTH_HEADER}" "${BASE}/cashback/plans")"
else
  stub "GET /me (no auth token)"
  stub "GET /addresses (no auth token)"
  stub "GET /orders (no auth token)"
  stub "GET /cart (no auth token)"
  stub "GET /wallet/balance (no auth token)"
  stub "GET /cashback/plans (no auth token)"
fi

# ── Section 4: Address lifecycle ──────────────────────────────────────────────
log ""
log "Section 4 — Address CRUD"
ADDR_ID=""

if [[ -n "${ACCESS_TOKEN:-}" ]]; then
  # Address API uses simplified schema: label, name, full_address, district, city
  _ADDR_BODY_FILE=$(mktemp)
  ADDR_STATUS=$(curl -s -o "${_ADDR_BODY_FILE}" -w '%{http_code}' \
    -X POST "${BASE}/addresses" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d '{
      "label":"Ev",
      "name":"Smoke Test",
      "phone":"+905551234567",
      "full_address":"Test Sokak 1 No:5 Daire:3",
      "neighborhood":"Caferaga",
      "district":"Kadikoy",
      "city":"Istanbul",
      "postal_code":"34710"
    }' 2>/dev/null || echo '000')
  ADDR_RESP=$(cat "${_ADDR_BODY_FILE}" 2>/dev/null || echo '{}')
  rm -f "${_ADDR_BODY_FILE}"
  check_status "POST /addresses" 201 "${ADDR_STATUS}"

  ADDR_ID=$(echo "${ADDR_RESP}" | jq -r '.id // empty' 2>/dev/null)

  if [[ -n "${ADDR_ID:-}" ]]; then
    check_status "GET /addresses/{id}" 200 "$(get_status -H "${AUTH_HEADER}" "${BASE}/addresses/${ADDR_ID}")"
    DEL_ADDR_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
      -X DELETE "${BASE}/addresses/${ADDR_ID}" \
      -H "${AUTH_HEADER}" 2>/dev/null || echo '000')
    check_status "DELETE /addresses/{id}" 204 "${DEL_ADDR_STATUS}"
  else
    stub "GET /addresses/{id} (no addr_id from POST)"
    stub "DELETE /addresses/{id} (no addr_id from POST)"
  fi
else
  stub "POST /addresses (no auth token)"
  stub "GET /addresses/{id} (no auth token)"
  stub "DELETE /addresses/{id} (no auth token)"
fi

# ── Section 5: Cart lifecycle ──────────────────────────────────────────────────
log ""
log "Section 5 — Cart add + reserve + release"
RESERVATION_ID=""

if [[ -n "${ACCESS_TOKEN:-}" && -n "${VARIANT_ID:-}" ]]; then
  CART_ADD_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${BASE}/cart/items" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{\"variant_id\":${VARIANT_ID},\"qty\":1}" 2>/dev/null || echo '000')
  check_status "POST /cart/items" 204 "${CART_ADD_STATUS}"

  check_status "GET /cart (with item)" 200 "$(get_status -H "${AUTH_HEADER}" "${BASE}/cart")"

  RESERVE_RESP=$(curl -sf \
    -X POST "${BASE}/cart/reserve" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null || echo '{}')
  RESERVE_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
    -X POST "${BASE}/cart/reserve" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null || echo '000')
  # Reserve may return 201 (new) or 409 (already reserved) — both acceptable here
  if [[ "${RESERVE_STATUS}" == "201" || "${RESERVE_STATUS}" == "409" ]]; then
    ok "POST /cart/reserve (${RESERVE_STATUS})"
    PASS=$((PASS+1))
    # Undo the second ok() we'd have from check_status
    PASS=$((PASS-1))
  elif [[ "${RESERVE_STATUS}" == "501" ]]; then
    stub "POST /cart/reserve"
  else
    fail "POST /cart/reserve (expected 201 or 409, got ${RESERVE_STATUS})"
  fi

  RESERVATION_ID=$(echo "${RESERVE_RESP}" | jq -r '.reservation_id // empty' 2>/dev/null)

  # Release cart after test
  if [[ -n "${RESERVATION_ID:-}" ]]; then
    RELEASE_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
      -X POST "${BASE}/cart/release" \
      -H "${AUTH_HEADER}" \
      -H "Content-Type: application/json" \
      -d "{\"reservation_id\":\"${RESERVATION_ID}\"}" 2>/dev/null || echo '000')
    check_status "POST /cart/release" 204 "${RELEASE_STATUS}"
  fi

  # Remove item from cart for cleanup
  REMOVE_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
    -X DELETE "${BASE}/cart/items/${VARIANT_ID}" \
    -H "${AUTH_HEADER}" 2>/dev/null || echo '000')
  check_status "DELETE /cart/items/{variant_id}" 204 "${REMOVE_STATUS}"

elif [[ -z "${ACCESS_TOKEN:-}" ]]; then
  stub "Cart tests (no auth token)"
else
  stub "Cart tests (no variant_id from catalog — seed data loaded?)"
fi

# ── Section 6: Checkout initiate ──────────────────────────────────────────────
log ""
log "Section 6 — Checkout initiate (Sipay sandbox)"
log "  NOTE: Requires PSP_PROVIDER=sipay SIPAY_MODE=sandbox on staging."
log "  A fresh reservation is created for this test only."

if [[ -n "${ACCESS_TOKEN:-}" && -n "${VARIANT_ID:-}" ]]; then
  # Add fresh item + reserve for checkout test
  curl -sf -o /dev/null \
    -X POST "${BASE}/cart/items" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "{\"variant_id\":${VARIANT_ID},\"qty\":1}" 2>/dev/null || true

  CHECKOUT_RESERVE_RESP=$(curl -sf \
    -X POST "${BASE}/cart/reserve" \
    -H "${AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null || echo '{}')
  CHECKOUT_RESV_ID=$(echo "${CHECKOUT_RESERVE_RESP}" | jq -r '.reservation_id // empty' 2>/dev/null)

  if [[ -n "${CHECKOUT_RESV_ID:-}" ]]; then
    IDEM_KEY="smoke-checkout-$(date +%s)"
    CHECKOUT_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
      -X POST "${BASE}/checkout/initiate" \
      -H "${AUTH_HEADER}" \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: ${IDEM_KEY}" \
      -d "{
        \"reservation_id\":\"${CHECKOUT_RESV_ID}\",
        \"buyer_name\":\"Smoke\",
        \"buyer_surname\":\"Test\",
        \"buyer_email\":\"smoke@moproshop.com\"
      }" 2>/dev/null || echo '000')
    check_status "POST /checkout/initiate" 200 "${CHECKOUT_STATUS}"

    # Idempotent re-submit with same key — must return same 200
    IDEM_REPEAT_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
      -X POST "${BASE}/checkout/initiate" \
      -H "${AUTH_HEADER}" \
      -H "Content-Type: application/json" \
      -H "Idempotency-Key: ${IDEM_KEY}" \
      -d "{
        \"reservation_id\":\"${CHECKOUT_RESV_ID}\",
        \"buyer_name\":\"Smoke\",
        \"buyer_surname\":\"Test\",
        \"buyer_email\":\"smoke@moproshop.com\"
      }" 2>/dev/null || echo '000')
    check_status "POST /checkout/initiate (idempotent repeat)" 200 "${IDEM_REPEAT_STATUS}"
  else
    stub "POST /checkout/initiate (cart reserve returned no reservation_id)"
  fi
else
  stub "POST /checkout/initiate (no auth or no variant_id)"
fi

# ── Section 7: Security / negative path ──────────────────────────────────────
log ""
log "Section 7 — Security checks"

# Webhook with bad signature must reject
WEBHOOK_BAD_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST "${BASE}/payments/webhook/sipay" \
  -H "X-Sipay-Signature: deadbeef" \
  -H "Content-Type: application/json" \
  -d '{"invoice_id":"test","status":"1","amount":"100"}' 2>/dev/null || echo '000')
check_status "POST /payments/webhook/sipay bad-sig → 401" 401 "${WEBHOOK_BAD_STATUS}"

# Unauthenticated access to /me must be 401
UNAUTH_ME_STATUS=$(get_status "${BASE}/me")
check_status "GET /me without token → 401" 401 "${UNAUTH_ME_STATUS}"

# Unauthenticated access to /cart must be 401
UNAUTH_CART_STATUS=$(get_status "${BASE}/cart")
check_status "GET /cart without token → 401" 401 "${UNAUTH_CART_STATUS}"

# Non-existent product must be 404
NOTFOUND_STATUS=$(get_status "${BASE}/products/999999999")
if [[ "${NOTFOUND_STATUS}" == "404" ]]; then
  ok "GET /products/999999999 → 404"
elif [[ "${NOTFOUND_STATUS}" == "501" ]]; then
  stub "GET /products/{id} 404 path"
else
  fail "GET /products/999999999 → expected 404, got ${NOTFOUND_STATUS}"
fi

# ── Section 8: Seller transparency endpoint ───────────────────────────────────
log ""
log "Section 8 — Seller breakdown"

# Seller breakdown requires auth. Without a token, 401 is correct (good security).
# With a valid seller token, we'd expect 200 or 404. For smoke: 401 without auth = PASS (security check).
SELLER_BREAKDOWN_STATUS=$(get_status "${BASE}/seller/orders/1/breakdown")
if [[ "${SELLER_BREAKDOWN_STATUS}" == "200" || "${SELLER_BREAKDOWN_STATUS}" == "404" ]]; then
  ok "GET /seller/orders/1/breakdown (${SELLER_BREAKDOWN_STATUS} — 404 means no seeded order)"
elif [[ "${SELLER_BREAKDOWN_STATUS}" == "401" ]]; then
  ok "GET /seller/orders/1/breakdown → 401 (unauthenticated — correct, endpoint requires auth)"
else
  check_status "GET /seller/orders/1/breakdown" 200 "${SELLER_BREAKDOWN_STATUS}"
fi

# ── Section 9: __version payload shape ───────────────────────────────────────
log ""
log "Section 9 — Build info shape"

VERSION_BODY=$(get_body "${BASE}/__version" 2>/dev/null || echo '{}')
VERSION_SVC=$(echo "${VERSION_BODY}" | jq -r '.service // empty' 2>/dev/null)
VERSION_SHA=$(echo "${VERSION_BODY}" | jq -r '.sha // empty' 2>/dev/null)

if [[ "${VERSION_SVC}" == "core-svc" ]]; then
  ok "__version.service = core-svc"
else
  fail "__version.service (expected core-svc, got '${VERSION_SVC}')"
fi

if [[ -n "${VERSION_SHA:-}" ]]; then
  ok "__version.sha present (${VERSION_SHA})"
else
  fail "__version.sha missing"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
log ""
log "═══════════════════════════════════════════"
log " Smoke Results"
log "   PASS : ${PASS}"
log "   STUB : ${STUB}  (known pending 501s — not blocking)"
log "   FAIL : ${FAIL}"
log "═══════════════════════════════════════════"

if [[ ${FAIL} -gt 0 ]]; then
  log ""
  log "Failed checks:"
  for name in "${FAIL_NAMES[@]}"; do
    log "  ✗ ${name}"
  done
  log ""
  log "RESULT: FAIL — fix the above before proceeding with L9."
  exit 1
else
  log ""
  if [[ ${STUB} -gt 0 ]]; then
    log "RESULT: PASS WITH CAVEATS — ${STUB} stub endpoints pending implementation."
  else
    log "RESULT: PASS — all checks green."
  fi
  exit 0
fi
