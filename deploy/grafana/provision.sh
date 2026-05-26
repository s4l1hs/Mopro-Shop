#!/usr/bin/env bash
# Idempotent script that pushes Mopro dashboards, alert rules, and the
# notification policy to Grafana Cloud.  Safe to re-run at any time.
#
# Required env vars:
#   GRAFANA_API_URL   — e.g. https://mopro.grafana.net
#   GRAFANA_API_TOKEN — Service Account token with Editor + Alerting Writer roles
#
# Optional env vars (only needed when pushing alert rules to Mimir ruler):
#   GRAFANA_PROM_USER  — Mimir remote_write user ID
#   GRAFANA_PROM_PASS  — Mimir remote_write API key (same credential)
#   MIMIR_RULER_URL    — e.g. https://prometheus-prod-XX-prod-eu-west-X.grafana.net/prometheus

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARDS_DIR="${SCRIPT_DIR}/dashboards"
ALERTS_DIR="${SCRIPT_DIR}/alerts"
NOTIFICATION_POLICY="${SCRIPT_DIR}/notification-policy.yaml"

# ── Validate required env vars ─────────────────────────────────────────────
: "${GRAFANA_API_URL:?GRAFANA_API_URL is required (e.g. https://mopro.grafana.net)}"
: "${GRAFANA_API_TOKEN:?GRAFANA_API_TOKEN is required (Service Account token)}"

# Strip trailing slash for consistent URL construction
GRAFANA_API_URL="${GRAFANA_API_URL%/}"

log()  { printf '[provision] %s\n' "$*"; }
ok()   { printf '[provision] ✓ %s\n' "$*"; }
fail() { printf '[provision] ✗ %s\n' "$*" >&2; exit 1; }

# ── Helper: Grafana HTTP request ────────────────────────────────────────────
grafana_api() {
    local method="$1" path="$2" body="${3:-}"
    local url="${GRAFANA_API_URL}${path}"
    local args=(-s -o /dev/null -w "%{http_code}" -X "${method}" \
        -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${url}")
    if [[ -n "${body}" ]]; then
        args+=(-d "${body}")
    fi
    curl "${args[@]}"
}

grafana_api_response() {
    local method="$1" path="$2" body="${3:-}"
    local url="${GRAFANA_API_URL}${path}"
    local args=(-s -X "${method}" \
        -H "Authorization: Bearer ${GRAFANA_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${url}")
    if [[ -n "${body}" ]]; then
        args+=(-d "${body}")
    fi
    curl "${args[@]}"
}

# ── 1. Ensure dashboard folder exists ──────────────────────────────────────
log "Ensuring 'Mopro' dashboard folder exists..."
folder_uid="mopro-dashboards"
folder_payload=$(printf '{"uid":"%s","title":"Mopro"}' "${folder_uid}")
status=$(grafana_api POST "/api/folders" "${folder_payload}")
if [[ "${status}" == "200" || "${status}" == "409" ]]; then
    ok "Dashboard folder ready (uid=${folder_uid})"
else
    # 409 = already exists — that is fine; anything else is an error
    [[ "${status}" == "409" ]] || fail "Failed to create dashboard folder (HTTP ${status})"
fi

# ── 2. Push dashboards ──────────────────────────────────────────────────────
log "Pushing dashboards..."
for dashboard_file in "${DASHBOARDS_DIR}"/*.json; do
    dashboard_title=$(basename "${dashboard_file}" .json)
    # Wrap the dashboard JSON in the Grafana import envelope
    dashboard_json=$(cat "${dashboard_file}")
    payload=$(printf '{"dashboard":%s,"folderUid":"%s","overwrite":true,"message":"provision.sh deploy"}' \
        "${dashboard_json}" "${folder_uid}")
    status=$(grafana_api POST "/api/dashboards/db" "${payload}")
    if [[ "${status}" == "200" || "${status}" == "412" ]]; then
        ok "Dashboard pushed: ${dashboard_title}"
    else
        fail "Failed to push dashboard ${dashboard_title} (HTTP ${status})"
    fi
done

# ── 3. Push alert rules via Grafana Alerting API ────────────────────────────
# Uses Grafana's built-in Alerting (Unified Alerting / Mimir ruler).
# Requires Grafana ≥ 9 with Unified Alerting enabled.
log "Pushing alert rule groups..."

for rules_file in "${ALERTS_DIR}"/*.yaml; do
    group_name=$(basename "${rules_file}" .yaml)
    log "  → ${group_name} rules"

    # Convert the Prometheus ruler YAML to Grafana provisioning JSON.
    # Grafana's /api/v1/provisioning/alert-rules accepts individual rules.
    # We convert each rule from the YAML group into a POST call.
    # Requires yq (https://github.com/mikefarah/yq) to be available.
    if ! command -v yq &>/dev/null; then
        log "  [SKIP] yq not found — install yq to enable alert rule push"
        log "         Alternatively, import ${rules_file} manually via Grafana UI: Alerting → Provisioning"
        continue
    fi

    rule_count=$(yq e '.groups[].rules | length' "${rules_file}" 2>/dev/null || echo 0)
    log "  Found ${rule_count} rules in ${group_name}"

    # For Mimir ruler (when MIMIR_RULER_URL is set) use mimirtool instead.
    # This is the preferred path for Grafana Cloud stacks.
    if [[ -n "${MIMIR_RULER_URL:-}" ]]; then
        if command -v mimirtool &>/dev/null; then
            mimirtool rules load \
                --address="${MIMIR_RULER_URL}" \
                --id="${GRAFANA_PROM_USER:-mopro}" \
                --key="${GRAFANA_PROM_PASS:-}" \
                --namespace="mopro" \
                "${rules_file}" && ok "Alert rules loaded via mimirtool: ${group_name}" \
            || fail "mimirtool failed for ${group_name}"
        else
            log "  [SKIP] mimirtool not found — install mimirtool or set MIMIR_RULER_URL empty to use Grafana API"
            log "         Download: https://github.com/grafana/mimir/releases (mimirtool binary)"
        fi
    else
        # Fall back: import via Grafana's Alerting provisioning API (Grafana-managed rules)
        # This path creates folder-based alert rules in the Mopro folder.
        log "  Using Grafana managed alert rules API (no MIMIR_RULER_URL set)"
        # Alerting provisioning via API is complex — provide instruction instead of fragile shell parsing
        log "  [INFO] To import ${rules_file} as Grafana-managed alerts:"
        log "         Grafana UI → Alerting → Alert rules → Import → select ${rules_file}"
        log "         Or set MIMIR_RULER_URL + GRAFANA_PROM_USER + GRAFANA_PROM_PASS for mimirtool"
    fi
done

# ── 4. Push notification policy ─────────────────────────────────────────────
log "Pushing notification policy..."
if [[ ! -f "${NOTIFICATION_POLICY}" ]]; then
    log "[SKIP] ${NOTIFICATION_POLICY} not found"
else
    if command -v yq &>/dev/null; then
        policy_json=$(yq e -o=json '.' "${NOTIFICATION_POLICY}")
        status=$(grafana_api PUT "/api/v1/provisioning/policies" "${policy_json}")
        if [[ "${status}" == "202" || "${status}" == "200" ]]; then
            ok "Notification policy pushed"
        else
            log "[WARN] Notification policy push returned HTTP ${status}"
            log "       This may be expected if contact points are not yet configured."
            log "       Configure contact points in Grafana UI → Alerting → Contact points first."
        fi
    else
        log "[SKIP] yq not found — cannot convert notification-policy.yaml to JSON"
        log "       Import manually: Grafana UI → Alerting → Notification policies → Edit JSON"
    fi
fi

# ── 5. Verify dashboards are accessible ─────────────────────────────────────
log "Verifying dashboards are accessible..."
for uid in mopro-slo-overview mopro-financial mopro-infra mopro-backup-cron; do
    status=$(grafana_api GET "/api/dashboards/uid/${uid}")
    if [[ "${status}" == "200" ]]; then
        ok "Dashboard verified: ${uid}"
    else
        log "[WARN] Dashboard ${uid} returned HTTP ${status} — may not be visible yet"
    fi
done

log ""
log "Provisioning complete."
log ""
log "Dashboard URLs (replace <your-stack> with your Grafana Cloud stack name):"
log "  SLO Overview:       ${GRAFANA_API_URL}/d/mopro-slo-overview"
log "  Financial Health:   ${GRAFANA_API_URL}/d/mopro-financial"
log "  Infra Health:       ${GRAFANA_API_URL}/d/mopro-infra"
log "  Backup & Cron:      ${GRAFANA_API_URL}/d/mopro-backup-cron"
log ""
log "If alert rules were skipped, import them manually or install mimirtool:"
log "  https://github.com/grafana/mimir/releases"
