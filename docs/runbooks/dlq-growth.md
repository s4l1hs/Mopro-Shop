# Runbook: DlqGrowth

## Severity
warning

## What this means
The dead-letter queue (DLQ) for Redis Streams event consumers is receiving messages at a rate above 0.5 messages/second for at least 15 minutes (`mopro_eventbus_dlq_messages_total` rate > 0.5/s). Messages land in the DLQ when a consumer exhausts its retry budget without succeeding. DLQ growth means financial or operational events are not being processed — potentially blocking cashback plan creation, seller payouts, or notifications.

## Common causes
- A fin-svc consumer is rejecting events due to a schema mismatch after a deploy (event format changed without a version bump)
- A dependency is unavailable (postgres-ledger, Redis) causing the consumer to repeatedly fail and exhaust retries
- A specific event payload has a bug (nil field, invalid amount) that causes a panic in the consumer handler
- The consumer is trying to process events faster than the DB can handle, causing timeouts that drain the retry budget
- An outbox event was published with a malformed `idempotency_key`, causing the consumer to reject it

## Investigation steps
1. **Identify the affected consumer**: `mopro_eventbus_dlq_messages_total` labels include `service`, `consumer`, and `event_type` — check Grafana → Infra Health → "Event Bus Throughput"
2. **Inspect DLQ messages**: In Redis, examine the DLQ stream:
   ```bash
   docker exec redis redis-cli XRANGE mopro:dlq:<service>:<consumer> - + COUNT 10
   ```
3. **Check consumer logs**: `docker compose logs --tail=200 fin-svc | grep -E "dlq|DLQ|consumer error|retry exhausted"`
4. **Check if dependency is up**: for fin-svc consumers, verify `postgres-ledger` and `redis` are healthy
5. **Check for event schema change**: `git log --oneline -5` — did a deploy change an event struct? Compare the DLQ message payload with the current consumer's expected struct
6. **Check outbox lag**: Grafana → Infra Health → "Outbox Publisher Lag" — if lag is high, the outbox publisher may be the problem upstream

## Mitigation
- **If a schema mismatch after a deploy**: roll back the deploy (`make rollback SERVER=mopro@195.85.207.92`) OR write a migration consumer that handles both old and new format (v-bump the event topic)
- **If dependency unavailable**: fix the dependency first (see `docs/runbooks/api-down.md` or `docs/runbooks/db-conn-pool-exhausted.md`); then replay DLQ:
  ```bash
  docker exec redis redis-cli XRANGE mopro:dlq:<service>:<consumer> - + COUNT 100
  # After verifying the fix, re-publish the DLQ messages to the main stream
  ```
- **If a single bad event**: identify the `event_id` from the DLQ, investigate, and if safe to skip: `XDEL mopro:dlq:<service>:<consumer> <message-id>` (confirm with Finance if the event is financial)
- **If consumer is overloaded**: check if a batch size or concurrency setting can be reduced; the consumer may need throttling

## Escalation
- Slack: #mopro-eng (warning)
- If the affected consumer is `cashback-plan-creator` or `seller-payout-scheduler`: escalate to #mopro-panic and notify Finance — financial operations are blocked
- If DLQ count exceeds 1000 messages: escalate regardless of consumer type

## Post-incident
- Record affected consumer, event type, and root cause in incident doc
- Verify all DLQ messages were either replayed successfully or deliberately discarded (with Finance sign-off for financial events)
- Add a schema compatibility test (v1 + v2 payloads) to the event consumer test suite
- Review retry budget configuration: if retries are exhausting too quickly on transient failures, increase the retry window
