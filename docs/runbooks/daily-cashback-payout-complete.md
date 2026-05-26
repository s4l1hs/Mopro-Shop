# Runbook: DailyCashbackPayoutComplete

## Severity
info

## What this means
This is an informational alert, not a problem. `mopro_build_info` changed (a deploy succeeded) OR the daily/monthly financial cron jobs completed their runs. This fires to confirm that routine financial operations executed as expected.

There are two info alerts that use this runbook:
- **`DeploySucceeded`**: `changes(mopro_build_info[5m]) > 0` — a new image was deployed to one or more services
- **`DailyCashbackPayoutComplete`**: `mopro_job_last_run_status{job=~"cashback-monthly|seller-payout-daily"} == 1` — the cashback or payout cron completed successfully

## What to do

### If this is a `DeploySucceeded` alert
- No action required unless a warning or critical alert fires within 10 minutes of the deploy
- The alert annotation includes the `service`, `version`, and `buildtime` labels — use these to confirm which binary was updated
- If a regression appears: check `git log --oneline -5` to identify what changed, then `make rollback SERVER=mopro@195.85.207.92`

### If this is a `DailyCashbackPayoutComplete` alert
- No action required — this is a confirmation heartbeat
- **Cashback-monthly** fires on the 1st of each month after the cron completes
- **Seller-payout-daily** fires daily after `02:30 UTC` once the cron completes
- If you expect this alert but it does NOT fire, check:
  - Grafana → Backup & Cron Health → "Cron Last Run Status" — is the job showing FAILED?
  - `docker compose logs fin-svc | grep cashback-monthly` or `grep seller-payout-daily`
  - Run manually: `fin-svc --run-once --cron=cashback-monthly` or `fin-svc --run-once --cron=seller-payout-daily`

## Confirmation checklist (monthly, for cashback-monthly)
- Grafana → Financial Health → "Cashback Plans & Installments" → installments paid count increased
- Verify a sample user's wallet balance increased by their expected `monthly_coin_minor`
- No `LedgerImbalanced` alert fired in the same window

## Confirmation checklist (daily, for seller-payout-daily)
- Grafana → Financial Health → row for seller payouts (if panel added)
- Verify PSP transfer was initiated for expected payouts (check Sipay dashboard)
- No `SipayHandoffFailing` alert fired in the same window

## Escalation
- No escalation needed for info alerts
- If you expected this alert and it did not fire: treat as a warning and investigate the cron status
