#!/usr/bin/env bash
# Section E — Performance
# Sourced by launch-readiness.sh; uses pass/fail/warn and vds_get/vds_int.
# Checks local load-test reports (load-tests/reports/) and VDS caddy log 5xx count.

check_performance() {
  local SEC="E"
  local REPORTS_DIR="$REPO_ROOT/load-tests/reports"
  local NOW_EPOCH; NOW_EPOCH=$(date +%s)
  local SEVEN_DAYS=$(( 7 * 86400 ))

  # E1: Baseline report exists within the last 7 days
  local latest_md=""
  if [[ -d "$REPORTS_DIR" ]]; then
    latest_md=$(ls -1t "$REPORTS_DIR"/baseline-*.md 2>/dev/null | head -1 || true)
  fi

  if [[ -z "$latest_md" ]]; then
    fail "$SEC" "baseline-report-exists" "No baseline-*.md in load-tests/reports/ — run: ./run.sh baseline"
    # Skip SLO check — no report to parse
    warn "$SEC" "baseline-slos-pass" "Cannot check — no baseline report"
  else
    # Check report age
    local report_mtime; report_mtime=$(stat -f %m "$latest_md" 2>/dev/null || stat -c %Y "$latest_md" 2>/dev/null || echo 0)
    local age=$(( NOW_EPOCH - report_mtime ))
    if [[ "$age" -le "$SEVEN_DAYS" ]]; then
      local age_h=$(( age / 3600 ))
      pass "$SEC" "baseline-report-exists" "$(basename "$latest_md") — ${age_h}h old (≤7 days)"
    else
      local age_d=$(( age / 86400 ))
      warn "$SEC" "baseline-report-exists" "$(basename "$latest_md") is ${age_d} days old (want ≤7 days)"
    fi

    # E2: All latency SLOs pass in the baseline report (no ❌ on latency rows).
    # awk always exits 0 — avoids set -o pipefail firing on grep's exit-1-on-no-match.
    # Error-rate and check-pass ❌ are expected deferrals for pre-seed environment.
    local latency_fails
    latency_fails=$(awk 'BEGIN{n=0} /❌/ && /ms/{n++} END{print n}' "$latest_md" 2>/dev/null || echo "0")
    local error_fails
    error_fails=$(awk 'BEGIN{n=0} /❌/ && /(Error rate|Check pass)/{n++} END{print n}' "$latest_md" 2>/dev/null || echo "0")

    if [[ "$latency_fails" -eq 0 ]]; then
      pass "$SEC" "baseline-slos-pass" "All latency SLOs ✅ in baseline report"
    else
      fail "$SEC" "baseline-slos-pass" "${latency_fails} latency SLO(s) ❌ in $(basename "$latest_md")"
    fi

    # E3: Error-rate/check-pass SLOs (WARN if still failing — expected until products seeded)
    if [[ "$error_fails" -gt 0 ]]; then
      warn "$SEC" "baseline-error-rate" "Error-rate/check-pass ❌ in baseline — expected deferral (no products seeded)"
    else
      pass "$SEC" "baseline-error-rate" "Error-rate and check-pass ✅"
    fi
  fi

  # E4: No 5xx responses in Caddy logs in the last 1 hour
  local fivex; fivex=$(vds_int FIVEX_1H)
  if [[ "$fivex" -eq 0 ]]; then
    pass "$SEC" "no-5xx-1h" "0 5xx responses in last 1h"
  else
    fail "$SEC" "no-5xx-1h" "${fivex} 5xx response(s) in last 1h — investigate before launch"
  fi
}
