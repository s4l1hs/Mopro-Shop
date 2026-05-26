# Runbook: DbConnPoolExhausted

## Severity
critical

## What this means
The pgx connection pool for a service has `acquired_conns / max_conns > 95%` for at least 3 minutes. New requests requiring a DB connection will queue and eventually time out, causing cascading 500 errors.

## Common causes
- A slow query or missing index is holding connections open far longer than usual
- A long-running transaction was left open (uncommitted) by a bug or a dead goroutine
- Traffic spike: more concurrent requests than the pool can serve
- PgBouncer `max_client_conn` or `pool_size` set too low relative to actual load
- A background job (reconcile, payout, cashback cron) is running a large batch holding many connections
- Connection leak: goroutine exits without returning its connection to the pool

## Investigation steps
1. **Identify service**: Grafana → Infra Health → "Pool Utilization" panel — which `service/db` label is > 95%
2. **Check active queries**: On the VDS, connect to the DB and run:
   ```sql
   SELECT pid, now() - query_start AS duration, state, left(query, 120) AS query
   FROM pg_stat_activity
   WHERE state != 'idle'
   ORDER BY duration DESC LIMIT 20;
   ```
3. **Check long-running transactions**:
   ```sql
   SELECT pid, now() - xact_start AS tx_duration, state, left(query, 120)
   FROM pg_stat_activity
   WHERE xact_start IS NOT NULL
   ORDER BY tx_duration DESC LIMIT 10;
   ```
4. **Check PgBouncer stats**: `docker exec pgbouncer-ecom psql -h 127.0.0.1 -p 5432 -U pgbouncer pgbouncer -c "SHOW POOLS;"` (replace with `pgbouncer-ledger` for fin-svc)
5. **Check for connection leak**: `docker compose logs --tail=200 <service>` — look for goroutine panics or `context canceled` errors that may have skipped `conn.Release()`
6. **Check query latency**: Grafana → Infra Health → "DB Query Latency p95 by Service + Operation" — a sudden latency spike usually precedes pool exhaustion

## Mitigation
- **If a long-running query is blocking**: `SELECT pg_terminate_backend(<pid>);` — this kills the specific backend; the service will retry
- **If a stuck transaction**: `SELECT pg_terminate_backend(<pid>);` to terminate; investigate the code path
- **If PgBouncer pool_size is too small**: edit `.env` to raise `PGBOUNCER_POOL_SIZE` (check headroom against `CLAUDE.md §7` limits), then `docker compose -f deploy/docker-compose.prod.yml restart pgbouncer-ecom`
- **If a cron job is holding connections**: wait for the cron to finish; if hung, `docker compose restart <service>` to terminate all connections
- **Emergency**: restart the affected service to flush its pool; connections held by the old process are released immediately

## Escalation
- Slack: #mopro-panic (if checkout is impacted)
- PagerDuty escalation policy: Platform → On-Call Engineer
- If fin-svc (`postgres-ledger` pool): also ping Finance team

## Post-incident
- Record the offending query + execution plan in incident doc
- Add a `statement_timeout` to the slow query's module context if appropriate
- Review PgBouncer `pool_size` against peak load observed; adjust if necessary
- Add a regression test that verifies the query has an index-supporting execution plan
