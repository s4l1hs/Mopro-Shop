#!/usr/bin/env bash
# Section A — Infrastructure
# Sourced by launch-readiness.sh; uses pass/fail/warn and vds_get/vds_int.

check_infrastructure() {
  local SEC="A"

  # A1: Expected container count (12 running including one-shot init done)
  local containers; containers=$(vds_int CONTAINERS_RUNNING)
  if [[ "$containers" -ge 12 ]]; then
    pass "$SEC" "containers-running" "${containers} running (≥12)"
  else
    fail "$SEC" "containers-running" "${containers} running (want ≥12) — check: sudo docker ps"
  fi

  # A2: Disk usage < 70 %
  local disk; disk=$(vds_int DISK_USE_PCT)
  if [[ "$disk" -lt 70 ]]; then
    pass "$SEC" "disk-usage" "${disk}% used (< 70%)"
  elif [[ "$disk" -lt 85 ]]; then
    warn "$SEC" "disk-usage" "${disk}% used (warn threshold 70%; critical 85%)"
  else
    fail "$SEC" "disk-usage" "${disk}% used — CRITICAL (> 85%)"
  fi

  # A3: PostgreSQL 16.x (version_num >= 160000)
  local pgnum; pgnum=$(vds_int POSTGRES_VERSION_NUM)
  if [[ "$pgnum" -ge 160000 ]]; then
    pass "$SEC" "postgres-version" "version_num=${pgnum} (≥160000 = 16.x)"
  else
    fail "$SEC" "postgres-version" "version_num=${pgnum} (want ≥160000 for 16.x)"
  fi

  # A4: Redis responds PONG
  local rpong; rpong=$(vds_get REDIS_PING)
  if [[ "$rpong" == "PONG" ]]; then
    pass "$SEC" "redis-pong" "PONG received"
  else
    fail "$SEC" "redis-pong" "got '${rpong}' (want PONG) — check REDIS_PASSWORD"
  fi

  # A5: Port 443 reachable
  local p443; p443=$(vds_int PORT_443)
  if [[ "$p443" -eq 1 ]]; then
    pass "$SEC" "port-443-open" "localhost:443 reachable"
  else
    fail "$SEC" "port-443-open" "localhost:443 not reachable — Caddy down?"
  fi

  # A6: Port 80 reachable (Caddy redirects to 443)
  local p80; p80=$(vds_int PORT_80)
  if [[ "$p80" -eq 1 ]]; then
    pass "$SEC" "port-80-open" "localhost:80 reachable (redirect)"
  else
    warn "$SEC" "port-80-open" "localhost:80 not reachable — HTTP→HTTPS redirect may be broken"
  fi
}
