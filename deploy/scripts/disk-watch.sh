#!/usr/bin/env bash
# disk-watch.sh — Mopro VDS disk pressure monitor.
# Run every 60s via disk-watch.timer. Escalates through INFO→WARN→ERROR→PANIC
# thresholds with Slack + PagerDuty alerts. At 92% PANIC, sets the Redis key
# checked by the checkout endpoint to return 503.
#
# FORBIDDEN: docker volume prune — would destroy postgres-ecom / postgres-ledger data.
set -euo pipefail

# ── Configuration (all overridable via env / EnvironmentFile) ─────────────────
LOG_FILE="${DISK_WATCH_LOG:-/var/log/disk-watch.log}"
LOG_MAX_BYTES="${DISK_WATCH_LOG_MAX_BYTES:-104857600}"   # 100 MB
STATE_DIR="${DISK_WATCH_STATE_DIR:-/var/run/disk-watch}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
SLACK_WEBHOOK="${SLACK_PANIC_WEBHOOK:-}"
PD_ROUTING_KEY="${PAGERDUTY_ROUTING_KEY:-}"
HYSTERESIS_SECS=300   # 5 minutes between repeated alerts for the same threshold

# ── Thresholds ────────────────────────────────────────────────────────────────
readonly T_INFO=70
readonly T_WARN=80
readonly T_WARN_PD=85
readonly T_ERROR=90
readonly T_PANIC=92
readonly T_RECOVERY=80   # disk must drop below this to exit panic mode

DISK_PCT=0   # set by get_disk_pct

# ── Helpers ───────────────────────────────────────────────────────────────────

get_disk_pct() {
    DISK_PCT=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
}

ts_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log_json() {
    local level="$1" msg="$2"
    shift 2
    # Build optional extra key=value pairs as JSON
    local extra=""
    while [[ $# -ge 2 ]]; do
        extra="${extra},\"$1\":\"$2\""
        shift 2
    done
    printf '{"ts":"%s","level":"%s","msg":"%s","disk_pct":%d%s}\n' \
        "$(ts_now)" "$level" "$msg" "$DISK_PCT" "$extra" >> "$LOG_FILE"
}

# should_alert THRESHOLD — returns 0 (true) if hysteresis window has elapsed.
should_alert() {
    local threshold="$1"
    local state_file="${STATE_DIR}/last_alert_${threshold}"
    local now
    now=$(date +%s)
    if [[ -f "$state_file" ]]; then
        local last
        last=$(cat "$state_file" 2>/dev/null || echo 0)
        if (( now - last < HYSTERESIS_SECS )); then
            return 1   # within hysteresis window — skip
        fi
    fi
    echo "$now" > "$state_file"
    return 0
}

send_slack() {
    [[ -z "$SLACK_WEBHOOK" ]] && return 0
    local msg="$1"
    # Escape double-quotes in message
    local escaped="${msg//\"/\\\"}"
    curl -s -o /dev/null --max-time 5 -X POST "$SLACK_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"${escaped}\"}" || true
}

send_pagerduty() {
    [[ -z "$PD_ROUTING_KEY" ]] && return 0
    local summary="$1" severity="$2" dedup_key="$3"
    curl -s -o /dev/null --max-time 10 \
        -X POST "https://events.pagerduty.com/v2/enqueue" \
        -H "Content-Type: application/json" \
        -d "{
            \"routing_key\":\"${PD_ROUTING_KEY}\",
            \"event_action\":\"trigger\",
            \"dedup_key\":\"${dedup_key}\",
            \"payload\":{
                \"summary\":\"${summary}\",
                \"severity\":\"${severity}\",
                \"source\":\"mopro-disk-watch\"
            }
        }" || true
}

resolve_pagerduty() {
    [[ -z "$PD_ROUTING_KEY" ]] && return 0
    local dedup_key="$1"
    curl -s -o /dev/null --max-time 10 \
        -X POST "https://events.pagerduty.com/v2/enqueue" \
        -H "Content-Type: application/json" \
        -d "{
            \"routing_key\":\"${PD_ROUTING_KEY}\",
            \"event_action\":\"resolve\",
            \"dedup_key\":\"${dedup_key}\"
        }" || true
}

# redis_cmd ARGS — runs a redis-cli command; no-op on failure (fail-open).
redis_cmd() {
    REDISCLI_AUTH="$REDIS_PASSWORD" \
        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null || true
}

redis_set_panic()  { redis_cmd SET panic:disk_full 1; }
redis_del_panic()  { redis_cmd DEL panic:disk_full; }

# truncate_large_logs — truncates any log file > 500 MB down to 50 MB.
# Targets /var/log and /opt/mopro/logs only; never touches DB data directories.
truncate_large_logs() {
    local dirs=("/var/log" "/opt/mopro/logs")
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r -d '' f; do
            truncate -s 52428800 "$f" || true   # 50 MB
        done < <(find "$d" -maxdepth 3 -name "*.log" -size +524288000c -print0 2>/dev/null)
    done
}

# rotate_log_if_needed — rotates the watch log itself when it exceeds LOG_MAX_BYTES.
rotate_log_if_needed() {
    [[ -f "$LOG_FILE" ]] || return 0
    local size
    size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if (( size > LOG_MAX_BYTES )); then
        mv "$LOG_FILE" "${LOG_FILE}.1"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

mkdir -p "$STATE_DIR"
rotate_log_if_needed
get_disk_pct

PANIC_STATE="${STATE_DIR}/panic_active"

# Recovery check: if we were in panic mode and disk has recovered, clear it.
if [[ -f "$PANIC_STATE" ]] && (( DISK_PCT < T_RECOVERY )); then
    log_json "INFO" "disk_pressure_resolved"
    redis_del_panic
    rm -f "$PANIC_STATE"
    # Resolve all threshold incidents that may have been opened.
    resolve_pagerduty "mopro-disk-92"
    resolve_pagerduty "mopro-disk-90"
    resolve_pagerduty "mopro-disk-85"
fi

# Threshold dispatch (highest first).
if (( DISK_PCT >= T_PANIC )); then
    log_json "PANIC" "disk_panic_mode" "action" "redis_set+docker_prune+log_truncate"
    touch "$PANIC_STATE"
    redis_set_panic
    docker image prune -f 2>/dev/null || true
    docker container prune -f --filter "until=1h" 2>/dev/null || true
    # NEVER docker volume prune — would destroy postgres data (CLAUDE.md §2.2)
    truncate_large_logs
    if should_alert "92"; then
        send_slack ":rotating_light: *DISK PANIC ${DISK_PCT}%* on mopro VDS — checkout disabled, pruning containers/images, log truncation in progress"
        send_pagerduty "DISK PANIC ${DISK_PCT}% — mopro checkout disabled" "critical" "mopro-disk-92"
    fi

elif (( DISK_PCT >= T_ERROR )); then
    log_json "ERROR" "disk_critical" "action" "docker_image_prune"
    docker image prune -f 2>/dev/null || true
    if should_alert "90"; then
        send_slack ":fire: *Disk ${DISK_PCT}%* on mopro VDS — image prune triggered, approaching panic threshold"
        send_pagerduty "Disk ${DISK_PCT}% on mopro VDS — approaching panic threshold" "error" "mopro-disk-90"
    fi

elif (( DISK_PCT >= T_WARN_PD )); then
    log_json "WARN" "disk_high"
    if should_alert "85"; then
        send_slack ":warning: *Disk ${DISK_PCT}%* on mopro VDS — action required"
        send_pagerduty "Disk ${DISK_PCT}% on mopro VDS — action required" "warning" "mopro-disk-85"
    fi

elif (( DISK_PCT >= T_WARN )); then
    log_json "WARN" "disk_warning"
    if should_alert "80"; then
        send_slack ":warning: *Disk ${DISK_PCT}%* on mopro VDS — monitor closely"
    fi

elif (( DISK_PCT >= T_INFO )); then
    log_json "INFO" "disk_usage_elevated"

fi

exit 0
