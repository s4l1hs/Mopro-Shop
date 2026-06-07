# Runbook: ApiDown

## Severity
critical

## What this means
One or more of the three Mopro service binaries (`core-svc`, `fin-svc`, `jobs-svc`) has been unreachable by the Prometheus scrape target for at least 2 minutes. The Prometheus `up` metric for that job is 0.

## Common causes
- Container crashed (OOM kill, panic at startup, or unhandled goroutine panic)
- Docker daemon restarted and the container did not come back up
- PgBouncer or Redis down preventing service startup healthcheck from passing
- Misconfigured environment variable causing a fatal startup panic
- Caddy misconfiguration causing `/metrics` to be unreachable (scrape target changed)
- Grafana Agent lost network connectivity to the service's metrics port

## Investigation steps
1. **Identify which service**: Grafana → SLO Overview or the PagerDuty alert body — note the `job` label
2. **Check container state**: `docker ps | grep <service>` — look for `Exiting`, `Restarting`, or absent
3. **Check container logs**: `docker compose -f deploy/docker-compose.prod.yml logs --tail=200 <service>` — look for `panic`, `fatal`, `SIGKILL`
4. **Check restart count**: `docker inspect <service> | jq '.[].RestartCount'` — count > 2 indicates repeated crash-restart loop
5. **Check dependencies**: `docker ps | grep -E 'pgbouncer|redis'` — a missing dependency causes startup failure
6. **Test healthz directly**: `curl -sf http://localhost:<port>/healthz` from the VDS — non-200 or connection refused confirms the service is not listening
7. **Check host memory**: `free -h` — if available < 1 GB, OOM pressure may be killing containers

## Mitigation
- **If crash-loop**: `docker compose -f deploy/docker-compose.prod.yml restart <service>` — if it keeps dying, check logs before trying again
- **If OOM**: `docker stats --no-stream` to confirm; raise mem_limit temporarily in `.env` per `INFRASTRUCTURE.md`; note the Resource Limits table in `CLAUDE.md §7` — do not permanently raise without CFO review
- **If dependency down**: restart pgbouncer first: `docker compose -f deploy/docker-compose.prod.yml restart pgbouncer-ecom` (or `pgbouncer-ledger` for fin-svc), then restart the service
- **If bad env var**: inspect `.env` on the VDS at `/opt/mopro/.env`; correct the offending value; restart the container
- **Emergency rollback**: roll back to the previous build per `deploy/RUNBOOK.md` § "Rollback manually" (pinned `:<full-sha>` GHCR tag)

## Escalation
- Slack: #mopro-panic immediately (all three services down = full outage)
- PagerDuty escalation policy: Platform → On-Call Engineer
- If fin-svc is down: also alert Finance team (cashback and payout engines are offline)

## Post-incident
- Record root cause (OOM / config / dependency / deploy) in incident doc
- If OOM: add memory profiling run to post-incident checklist
- If startup panic: add a pre-deploy config validation step to CI
- If dependency: verify Docker `depends_on` health-check conditions in `docker-compose.prod.yml`
