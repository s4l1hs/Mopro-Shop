#!/usr/bin/env bash
# Section G — Backups
# Sourced by launch-readiness.sh; uses pass/fail/warn and vds_get/vds_int.
# Both checks are WARN (not FAIL) — backups are a pre-launch goal, not a hard blocker.

check_backups() {
  local SEC="G"

  # G1: mopro-backup.timer is enabled and active (systemd)
  local btimer; btimer=$(vds_get BACKUP_TIMER_STATUS)
  if [[ "$btimer" == "active" ]]; then
    pass "$SEC" "backup-timer-active" "mopro-backup.timer is active"
  else
    warn "$SEC" "backup-timer-active" "mopro-backup.timer status='${btimer:-unknown}' — run install-backup.sh"
  fi

  # G2: Healthchecks.io UUID for backup cron configured (for dead-man alerting)
  local hc_backup; hc_backup=$(vds_get HC_BACKUP_UUID)
  if [[ -n "$hc_backup" ]]; then
    pass "$SEC" "backup-healthcheck-uuid" "HEALTHCHECK_BACKUP_UUID configured"
  else
    warn "$SEC" "backup-healthcheck-uuid" "HEALTHCHECK_BACKUP_UUID empty — silent backup failures possible"
  fi

  # G3: Healthchecks.io UUID for restore drill configured
  local hc_restore; hc_restore=$(vds_get HC_RESTORE_UUID)
  if [[ -n "$hc_restore" ]]; then
    pass "$SEC" "restore-healthcheck-uuid" "HEALTHCHECK_RESTORE_UUID configured"
  else
    warn "$SEC" "restore-healthcheck-uuid" "HEALTHCHECK_RESTORE_UUID empty — restore drills unmonitored"
  fi
}
