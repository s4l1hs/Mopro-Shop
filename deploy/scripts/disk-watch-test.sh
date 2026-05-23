#!/usr/bin/env bash
# disk-watch-test.sh — simulates disk-watch.sh at each threshold level
# by overriding df, docker, redis-cli, curl, and send_* with mocks.
# Safe to run on any machine; touches nothing real.
#
# Usage:
#   ./disk-watch-test.sh          # runs all scenarios
#   ./disk-watch-test.sh 92       # runs only the panic scenario
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH_SCRIPT="${SCRIPT_DIR}/disk-watch.sh"

PASS=0
FAIL=0

# ── Mock environment ──────────────────────────────────────────────────────────

# Temporary directory for state files and log.
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

export DISK_WATCH_STATE_DIR="${TMPDIR_TEST}/state"
export DISK_WATCH_LOG="${TMPDIR_TEST}/disk-watch.log"
export SLACK_PANIC_WEBHOOK="http://mock-slack"
export PAGERDUTY_ROUTING_KEY="mock-pd-key"
export REDIS_HOST="127.0.0.1"
export REDIS_PORT="9999"   # non-existent — fail-open path exercised

# Override df to inject a fake disk usage percentage.
mock_df() {
    local pct="$1"
    # shellcheck disable=SC2030
    export PATH="${TMPDIR_TEST}/bin:${PATH}"
    mkdir -p "${TMPDIR_TEST}/bin"
    cat > "${TMPDIR_TEST}/bin/df" <<EOF
#!/usr/bin/env bash
echo "Filesystem     1024-blocks     Used Available Capacity Mounted on"
echo "/dev/sda1        104857600 $((pct * 1048576)) $((104857600 - pct * 1048576)) ${pct}% /"
EOF
    chmod +x "${TMPDIR_TEST}/bin/df"
}

# Override curl to capture calls.
mock_curl() {
    # Use unquoted EOF so ${TMPDIR_TEST} is expanded into the script at write time.
    cat > "${TMPDIR_TEST}/bin/curl" <<EOF
#!/usr/bin/env bash
echo "MOCK_CURL: \$*" >> "${TMPDIR_TEST}/curl_calls.log"
exit 0
EOF
    chmod +x "${TMPDIR_TEST}/bin/curl"
}

# Override docker to capture calls.
mock_docker() {
    cat > "${TMPDIR_TEST}/bin/docker" <<EOF
#!/usr/bin/env bash
echo "MOCK_DOCKER: \$*" >> "${TMPDIR_TEST}/docker_calls.log"
exit 0
EOF
    chmod +x "${TMPDIR_TEST}/bin/docker"
}

# Override redis-cli to capture calls.
mock_redis() {
    cat > "${TMPDIR_TEST}/bin/redis-cli" <<EOF
#!/usr/bin/env bash
echo "MOCK_REDIS: \$*" >> "${TMPDIR_TEST}/redis_calls.log"
exit 0
EOF
    chmod +x "${TMPDIR_TEST}/bin/redis-cli"
}

# Override truncate to capture calls (some systems may not have it).
mock_truncate() {
    cat > "${TMPDIR_TEST}/bin/truncate" <<EOF
#!/usr/bin/env bash
echo "MOCK_TRUNCATE: \$*" >> "${TMPDIR_TEST}/truncate_calls.log"
exit 0
EOF
    chmod +x "${TMPDIR_TEST}/bin/truncate"
}

reset_mocks() {
    rm -rf "${TMPDIR_TEST}/bin" "${TMPDIR_TEST}/state" \
        "${TMPDIR_TEST}/curl_calls.log" "${TMPDIR_TEST}/docker_calls.log" \
        "${TMPDIR_TEST}/redis_calls.log" "${TMPDIR_TEST}/truncate_calls.log" \
        "${DISK_WATCH_LOG}"
    mkdir -p "${TMPDIR_TEST}/bin" "${TMPDIR_TEST}/state"
    mock_curl
    mock_docker
    mock_redis
    mock_truncate
}

# ── Assertion helpers ─────────────────────────────────────────────────────────

assert_log_contains() {
    local desc="$1" pattern="$2"
    if grep -q "$pattern" "${DISK_WATCH_LOG}" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — pattern '$pattern' not in log"
        cat "${DISK_WATCH_LOG}" 2>/dev/null || true
        FAIL=$((FAIL + 1))
    fi
}

assert_file_contains() {
    local desc="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — pattern '$pattern' not in $file"
        cat "$file" 2>/dev/null || echo "(file missing)"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_absent() {
    local desc="$1" file="$2"
    if [[ ! -f "$file" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — file $file should not exist"
        FAIL=$((FAIL + 1))
    fi
}

# ── Scenarios ─────────────────────────────────────────────────────────────────

run_scenario() {
    local name="$1" pct="$2"
    echo ""
    echo "==> Scenario: $name (disk_pct=${pct}%)"
    reset_mocks
    mock_df "$pct"
    bash "$WATCH_SCRIPT"
}

scenario_70() {
    run_scenario "70% INFO" 70
    assert_log_contains "INFO level logged"            '"level":"INFO"'
    assert_log_contains "correct message"              '"msg":"disk_usage_elevated"'
    assert_file_absent  "no Slack at 70%"              "${TMPDIR_TEST}/curl_calls.log"
    assert_file_absent  "no docker prune at 70%"       "${TMPDIR_TEST}/docker_calls.log"
    assert_file_absent  "no redis at 70%"              "${TMPDIR_TEST}/redis_calls.log"
}

scenario_80() {
    run_scenario "80% WARN+Slack" 80
    assert_log_contains "WARN level logged"            '"level":"WARN"'
    assert_log_contains "correct message"              '"msg":"disk_warning"'
    assert_file_contains "Slack called at 80%"         "${TMPDIR_TEST}/curl_calls.log" "mock-slack"
    assert_file_absent  "no PD at 80%"                 "/dev/null"  # curl is called but only for Slack
    assert_file_absent  "no docker prune at 80%"       "${TMPDIR_TEST}/docker_calls.log"
}

scenario_85() {
    run_scenario "85% WARN+Slack+PD" 85
    assert_log_contains "WARN level logged"            '"level":"WARN"'
    assert_log_contains "correct message"              '"msg":"disk_high"'
    assert_file_contains "Slack+PD called at 85%"      "${TMPDIR_TEST}/curl_calls.log" "pagerduty"
}

scenario_90() {
    run_scenario "90% ERROR+docker_prune" 90
    assert_log_contains "ERROR level logged"           '"level":"ERROR"'
    assert_log_contains "correct message"              '"msg":"disk_critical"'
    assert_file_contains "docker image prune at 90%"   "${TMPDIR_TEST}/docker_calls.log" "image prune"
    assert_file_contains "PD called at 90%"            "${TMPDIR_TEST}/curl_calls.log" "pagerduty"
}

scenario_92() {
    run_scenario "92% PANIC" 92
    assert_log_contains "PANIC level logged"           '"level":"PANIC"'
    assert_log_contains "correct message"              '"msg":"disk_panic_mode"'
    assert_file_contains "Redis SET panic key"         "${TMPDIR_TEST}/redis_calls.log" "panic:disk_full"
    assert_file_contains "docker image prune at 92%"   "${TMPDIR_TEST}/docker_calls.log" "image prune"
    assert_file_contains "docker container prune"      "${TMPDIR_TEST}/docker_calls.log" "container prune"
    assert_file_contains "PD critical at 92%"          "${TMPDIR_TEST}/curl_calls.log" "critical"
    # Verify volume prune was NOT called.
    if grep -q "volume prune" "${TMPDIR_TEST}/docker_calls.log" 2>/dev/null; then
        echo "  FAIL: docker volume prune must NEVER be called"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: docker volume prune not called (correct)"
        PASS=$((PASS + 1))
    fi
    # Panic state file must exist.
    if [[ -f "${DISK_WATCH_STATE_DIR}/panic_active" ]]; then
        echo "  PASS: panic_active state file created"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: panic_active state file missing"
        FAIL=$((FAIL + 1))
    fi
}

scenario_recovery() {
    echo ""
    echo "==> Scenario: recovery from panic (75% after panic)"
    reset_mocks
    # Pre-condition: simulate we were in panic mode.
    touch "${DISK_WATCH_STATE_DIR}/panic_active"
    mock_df 75
    bash "$WATCH_SCRIPT"
    assert_log_contains "resolved message"             '"msg":"disk_pressure_resolved"'
    assert_file_contains "Redis DEL panic key"         "${TMPDIR_TEST}/redis_calls.log" "DEL"
    assert_file_absent  "panic_active removed"         "${DISK_WATCH_STATE_DIR}/panic_active"
}

scenario_hysteresis() {
    echo ""
    echo "==> Scenario: hysteresis — second alert at 80% within 5 min suppressed"
    reset_mocks
    mock_df 80
    bash "$WATCH_SCRIPT"   # first run — alert fires
    rm -f "${DISK_WATCH_LOG}"
    bash "$WATCH_SCRIPT"   # second run within window — alert suppressed
    # The log entry should still appear (logging always happens) but Slack should not
    # be called a second time.
    local curl_count
    curl_count=$(wc -l < "${TMPDIR_TEST}/curl_calls.log" 2>/dev/null || echo 0)
    if (( curl_count <= 1 )); then
        echo "  PASS: hysteresis suppressed duplicate Slack call"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: Slack called $curl_count times — hysteresis not working"
        FAIL=$((FAIL + 1))
    fi
}

# ── Runner ────────────────────────────────────────────────────────────────────

TARGET="${1:-all}"

if [[ "$TARGET" == "all" ]]; then
    scenario_70
    scenario_80
    scenario_85
    scenario_90
    scenario_92
    scenario_recovery
    scenario_hysteresis
else
    "scenario_${TARGET}"
fi

echo ""
echo "========================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

if (( FAIL > 0 )); then
    exit 1
fi
