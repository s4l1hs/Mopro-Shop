# Runbook: ApiLatencyP95High

## Severity
warning

## What this means
The p95 HTTP response latency across one or more services has exceeded 500 ms for at least 10 minutes (`histogram_quantile(0.95, ...) > 0.5`). This means 1 in 20 requests is slower than half a second — noticeable to users and a leading indicator of pool exhaustion or a slow query.

## Common causes
- A slow or missing-index DB query holding a request thread
- DB connection pool near-exhaustion causing requests to wait for a connection
- Redis latency spike (network issue, memory pressure causing eviction sweeps)
- Meilisearch slow search response (index too large or host CPU saturated)
- GC pressure in a service causing periodic stop-the-world pauses
- A new deploy introduced a non-indexed query or a N+1 query pattern
- High-volume background job (reconcile, payout cron) competing for DB connections

## Investigation steps
1. **Identify the service**: Grafana → SLO Overview → "Latency Distribution" panel — which `service` is spiking
2. **Check DB latency**: Grafana → Infra Health → "DB Query Latency p95 by Service + Operation" — is DB latency high for this service?
3. **Check Redis latency**: Grafana → Infra Health → "Redis Command Latency p95" — Redis-bound if spike correlates
4. **Identify the slow route**: Grafana → SLO Overview → "Top 10 Routes" table — which route has the highest p95
5. **Check pool utilization**: Grafana → Infra Health → "Pool Utilization" — if > 80%, connections are the bottleneck
6. **Check for slow queries**:
   ```sql
   SELECT query, calls, mean_exec_time, max_exec_time
   FROM pg_stat_statements
   ORDER BY mean_exec_time DESC LIMIT 20;
   ```
7. **Check for a recent deploy**: `git log --oneline -5` — correlate spike onset with deploy time
8. **Check host CPU**: Grafana → Infra Health → "CPU Utilization per Core" — host saturation

## Mitigation
- **If a slow query is found**: add a missing index or rewrite the query; deploy the fix; monitor latency
- **If pool is near-exhausted**: follow `docs/runbooks/db-conn-pool-exhausted.md`
- **If deploy caused it**: `make rollback SERVER=mopro@195.85.207.92` if latency is user-impacting
- **If Redis latency**: check `docker stats --no-stream redis` for memory pressure; `docker compose restart redis` as a last resort (brief unavailability, services recover automatically)
- **If Meilisearch**: check index size and host CPU; consider reducing concurrent search requests or adding a rate limit

## Escalation
- Slack: #mopro-eng (warning — does not require immediate page)
- Escalate to #mopro-panic if p95 > 2s or if checkout conversion is visibly declining

## Post-incident
- Record which route was slow and the root cause in the incident doc
- Add the slow query to the regression test suite with `EXPLAIN ANALYZE` coverage
- If a deploy caused it, add the query/route to the pre-deploy smoke test checklist
