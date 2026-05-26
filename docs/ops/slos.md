# SLO Definitions — Mopro Platform

> All SLOs are measured against production traffic. Alert thresholds are conservative baselines;
> tune after the first 30-day production window (L9 smoke pass). Every SLI has a corresponding
> alert rule in `deploy/grafana/alerts/`.

---

## SLI 1 — API Availability

| | |
|---|---|
| **Target** | 99.5% successful requests over a 30-day rolling window |
| **Window** | 30d rolling |
| **Scope** | All three services (core-svc, fin-svc, jobs-svc) |

**Numerator** — successful requests (2xx + 3xx):
```promql
sum(rate(mopro_http_requests_total{status!~"5.."}[30d]))
```

**Denominator** — all non-client-error requests (excl. 4xx to avoid penalising client mistakes):
```promql
sum(rate(mopro_http_requests_total{status!~"4.."}[30d]))
```

**SLI expression**:
```promql
100 * (
  sum(rate(mopro_http_requests_total{status!~"5.."}[30d]))
  / sum(rate(mopro_http_requests_total{status!~"4.."}[30d]))
)
```

**Alert threshold**: 5xx rate > 5 % over 5 min → `ApiErrorRateHigh` (critical)

**Error budget**: 0.5 % of 30d = ~3.6 hours per month.

---

## SLI 2 — API Latency p95

| | |
|---|---|
| **Target** | p95 latency < 500 ms |
| **Window** | 30d rolling |
| **Scope** | All services, all routes |

**SLI expression** (5-min window for alerting):
```promql
histogram_quantile(0.95,
  sum by (le, service) (
    rate(mopro_http_request_duration_seconds_bucket[5m])
  )
)
```

**Alert threshold**: p95 > 500 ms for 10 min → `ApiLatencyP95High` (warning)

---

## SLI 3 — API Latency p99

| | |
|---|---|
| **Target** | p99 latency < 2 000 ms |
| **Window** | 30d rolling |

**SLI expression**:
```promql
histogram_quantile(0.99,
  sum by (le, service) (
    rate(mopro_http_request_duration_seconds_bucket[5m])
  )
)
```

**Note**: No separate alert for p99 at launch; the p95 alert catches degradation early enough.

---

## SLI 4 — Checkout Completion Rate

| | |
|---|---|
| **Target** | > 70 % of payment intents reach `captured` within 10 min |
| **Window** | 7d rolling |

**Numerator** — orders that transitioned pending_payment → captured:
```promql
sum(rate(mopro_order_status_transitions_total{from="pending_payment",to="captured"}[7d]))
```

**Denominator** — all orders created (pending_payment entered):
```promql
sum(rate(mopro_order_status_transitions_total{from="created",to="pending_payment"}[7d]))
```

**Alert threshold**: abandonment rate > 40 % over 30 min → `CheckoutAbandonmentSpike` (warning)

---

## SLI 5 — Ledger Reconciliation Balance

| | |
|---|---|
| **Target** | 100 % balanced D=C across all journal entries |
| **Window** | Per run (weekly) |

**SLI expression**:
```promql
mopro_job_last_run_status{job="ledger-reconcile"} == 0
```

**Alert threshold**: last run status = 0 (failed/imbalanced) for 1 min → `LedgerImbalanced` (critical)

**Note**: A `0` gauge after startup means the cron ran and found a discrepancy. The gauge is never
pre-set to 0 — it starts unset (no series) and transitions to 1 on first successful run.

---

## SLI 6 — Backup Freshness

| | |
|---|---|
| **Target** | Last successful backup < 26 hours old |
| **Window** | Continuous |

**SLI expression**:
```promql
time() - mopro_backup_last_success_timestamp_seconds > 93600
```

**Alert threshold**: backup older than 26 h for 10 min → `BackupStale` (critical)

**Note**: `mopro_backup_last_success_timestamp_seconds` is written by `backup-postgres.sh`
to `/var/lib/node_exporter/textfile_collector/mopro_backup.prom` and scraped via
the Grafana Agent node_exporter textfile integration.

---

## SLI 7 — Cashback Payout Accuracy

| | |
|---|---|
| **Target** | 100 % successful cashback installments per scheduled monthly run |
| **Window** | Per run (monthly) |

**SLI expression**:
```promql
mopro_job_last_run_status{job="cashback-monthly"} == 0
```

**Alert threshold**: last run = 0 (any plans failed) → `DailyCashbackPayoutComplete` info / raise to critical if > 0 plans fail.

**Supplementary metric** (installments paid count):
```promql
sum(rate(mopro_cashback_installments_paid_total[1d]))
```

---

## SLI 8 — Sipay 3DS Handoff Success

| | |
|---|---|
| **Target** | > 95 % of 3DS initiations succeed within 5 min |
| **Window** | 7d rolling |

**SLI expression** (5-min alerting window):
```promql
sum(rate(sipay_request_total{status!~"2.*"}[15m]))
/ sum(rate(sipay_request_total[15m]))
```

**Alert threshold**: error rate > 10 % for 15 min → `SipayHandoffFailing` (warning)

---

## Error Budget Policy

| SLI | Budget burn rate alert | Action |
|---|---|---|
| API Availability | > 5 % 5xx for 5 min | Page on-call (critical) |
| API Latency p95 | > 500 ms for 10 min | Slack warning |
| Checkout | > 40 % abandonment for 30 min | Slack + investigate |
| Ledger balance | Any imbalance | Page immediately (critical + panic Slack) |
| Backup | > 26 h stale | Page (critical) |

Exhausting the monthly error budget triggers a blameless post-incident process and a freeze on risky
deploys until the budget recovers to > 50 %.
