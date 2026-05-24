#!/usr/bin/env bash
# Section H — Operational Readiness
# Sourced by launch-readiness.sh; uses pass/fail/warn and vds_get/vds_int.

check_operational() {
  local SEC="H"

  # H1: disk-watch.timer active (OOM / disk-full early-warning systemd service)
  local dwtimer; dwtimer=$(vds_get DISK_WATCH_TIMER_STATUS)
  if [[ "$dwtimer" == "active" ]]; then
    pass "$SEC" "disk-watch-timer" "disk-watch.timer is active"
  else
    fail "$SEC" "disk-watch-timer" "disk-watch.timer status='${dwtimer:-not-found}' — run install-disk-watch.sh"
  fi

  # H2: Critical runbooks exist in docs/runbooks/
  local runbooks_dir="$REPO_ROOT/docs/runbooks"
  local runbooks_ok=1
  for rb in disaster-recovery.md restore-from-backup.md backup-failure.md disk-pressure.md launch-day.md; do
    if [[ ! -f "$runbooks_dir/$rb" ]]; then
      fail "$SEC" "runbook-${rb%.md}" "docs/runbooks/${rb} missing"
      runbooks_ok=0
    fi
  done
  [[ "$runbooks_ok" -eq 1 ]] && pass "$SEC" "runbooks-exist" "All 5 runbooks present"

  # H3: DLQ empty (unprocessed dead-letter events = data inconsistency risk)
  local dlq; dlq=$(vds_int DLQ_OPEN)
  if [[ "$dlq" -eq 0 ]]; then
    pass "$SEC" "dlq-empty" "0 open DLQ entries in wallet_schema.event_dlq"
  else
    fail "$SEC" "dlq-empty" "${dlq} open DLQ entry(s) — resolve before launch"
  fi

  # H4: Outbox lag = 0 on postgres-ecom (unpublished events mean dropped Redis Streams messages)
  local ob_ecom; ob_ecom=$(vds_int OUTBOX_LAG_ECOM)
  if [[ "$ob_ecom" -eq 0 ]]; then
    pass "$SEC" "outbox-lag-ecom" "0 unpublished outbox entries (ecom)"
  else
    fail "$SEC" "outbox-lag-ecom" "${ob_ecom} unpublished outbox row(s) on postgres-ecom — check outbox-publisher"
  fi

  # H5: Outbox lag = 0 on postgres-ledger (fin-svc events)
  local ob_ledger; ob_ledger=$(vds_int OUTBOX_LAG_LEDGER)
  if [[ "$ob_ledger" -eq 0 ]]; then
    pass "$SEC" "outbox-lag-ledger" "0 unpublished outbox entries (ledger)"
  else
    fail "$SEC" "outbox-lag-ledger" "${ob_ledger} unpublished outbox row(s) on postgres-ledger — check outbox-publisher"
  fi

  # H6: Manual go/no-go confirmation reminder (always WARN — operator must sign off)
  warn "$SEC" "manual-go-nogo" "Operator must review this report and give explicit go/no-go — see docs/runbooks/launch-day.md"
}
