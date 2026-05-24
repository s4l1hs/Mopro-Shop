#!/usr/bin/env bash
# Section D — Observability
# Sourced by launch-readiness.sh; uses pass/fail/warn and vds_get/vds_int.

check_observability() {
  local SEC="D"

  # D1–D3: Health endpoints (200) — checked from within Docker network on VDS
  for svc in core_svc fin_svc jobs_svc; do
    local key="HEALTHZ_$(echo "$svc" | tr '[:lower:]' '[:upper:]')"
    local name="${svc//_/-}"
    local st; st=$(vds_get "$key")
    if [[ "$st" == "200" ]]; then
      pass "$SEC" "healthz-${name}" "${name}/healthz → 200"
    elif [[ -z "$st" || "$st" == "0" ]]; then
      fail "$SEC" "healthz-${name}" "${name}/healthz — no response (container down?)"
    else
      fail "$SEC" "healthz-${name}" "${name}/healthz → HTTP ${st} (want 200)"
    fi
  done

  # D4–D6: Metrics endpoints reachable (Prometheus scrape target)
  for svc in core_svc fin_svc jobs_svc; do
    local key="METRICS_$(echo "$svc" | tr '[:lower:]' '[:upper:]')"
    local name="${svc//_/-}"
    local count; count=$(vds_int "$key")
    if [[ "$count" -ge 1 ]]; then
      pass "$SEC" "metrics-${name}" "${name}:9100+/metrics reachable"
    else
      fail "$SEC" "metrics-${name}" "${name} metrics endpoint not reachable — Prometheus blind"
    fi
  done

  # D7: Grafana credentials configured (WARN — optional pre-launch, needed for dashboards)
  local gu; gu=$(vds_get GRAFANA_PROM_USER)
  local gp; gp=$(vds_get GRAFANA_PROM_PASS)
  if [[ -n "$gu" && -n "$gp" ]]; then
    pass "$SEC" "grafana-creds" "GRAFANA_PROM_USER and PASS set"
  else
    warn "$SEC" "grafana-creds" "GRAFANA_PROM_USER/PASS empty — no remote metrics dashboard"
  fi

  # D8: Healthchecks.io UUIDs configured (WARN — needed for cron alerting)
  local hc_cashback; hc_cashback=$(vds_get HC_CASHBACK_UUID)
  local hc_payout;   hc_payout=$(vds_get HC_PAYOUT_UUID)
  if [[ -n "$hc_cashback" && -n "$hc_payout" ]]; then
    pass "$SEC" "healthchecks-uuids" "Cashback and payout cron UUIDs configured"
  else
    warn "$SEC" "healthchecks-uuids" "HC cashback=${hc_cashback:-empty} payout=${hc_payout:-empty} — cron failures will be silent"
  fi
}
