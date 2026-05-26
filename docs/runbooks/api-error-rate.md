# Runbook: ApiErrorRateHigh

## Severity
critical

## What this means
The 5xx error rate on one or more Mopro services has exceeded 5% of total requests for at least 5 minutes.

## Common causes
- A recent deploy introduced a regression (check `DeploySucceeded` info alert timeline)
- Postgres or Redis is unavailable, causing handler panics
- A specific route is returning 500 due to a query error or nil-pointer
- OOM kill of a container (service lost its DB connection pool)
- Misconfigured environment variable causing service startup panic

## Investigation steps
1. **Identify the service**: Grafana → SLO Overview → "Error Rate by Service" panel; note which `service` label is spiking
2. **Check recent logs**: `docker compose -f deploy/docker-compose.prod.yml logs --tail=200 <service>` — look for `level=ERROR`
3. **Check if container is up**: `docker ps | grep <service>` — OOM kills show restart count > 0
4. **Inspect the route**: In Grafana → SLO Overview → "Top 10 Routes" — which route has the highest error share
5. **Check DB connectivity**: `docker exec <service> wget -qO- http://localhost:<port>/healthz` — non-200 means the service is broken
6. **Check deploy timing**: `git log --oneline -5` — correlate with alert start time

## Mitigation
- **If a deploy caused it**: `make rollback SERVER=mopro@195.85.207.92` — this re-deploys the previous image
- **If OOM**: raise container memory limit temporarily in `.env`, restart: `docker compose -f deploy/docker-compose.prod.yml up -d <service>`
- **If DB unreachable**: check `docker ps | grep pgbouncer` and postgres containers; restart pgbouncer first
- **If specific route**: add a feature flag or emergency disable in `cmd/<service>/main.go`, redeploy

## Escalation
- Slack: #mopro-panic (if checkout is impacted)
- PagerDuty escalation policy: Platform → On-Call Engineer
- If financial data integrity suspected: also ping Finance team

## Post-incident
- Record route + root cause in incident doc
- Add route-level error rate panel to SLO Overview if the route was not visible
- If a deploy caused it, add a pre-deploy smoke test for the affected endpoint
