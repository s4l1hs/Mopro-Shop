# Observability — Mopro Platform

All telemetry is shipped by a single **Grafana Agent** container to Grafana Cloud Free. No SDK changes are needed to add a new pipeline; only the agent config changes.

---

## Architecture

```
core-svc  ─┐                        ┌─ Mimir  (metrics)
fin-svc   ─┼─ Grafana Agent ──────► ├─ Loki   (logs)
jobs-svc  ─┘                        └─ Tempo  (traces)
```

| Signal  | Path                                         | Protocol          |
|---------|----------------------------------------------|-------------------|
| Metrics | `<svc>:9100-9102/metrics` → Agent → Mimir    | Prometheus scrape + remote_write |
| Logs    | container stdout → Docker SD → Agent → Loki  | Loki push API     |
| Traces  | `<svc>` OTLP gRPC → `grafana-agent:4317` → Tempo | OTLP/gRPC → Tempo remote_write |

---

## Environment Variables

All six vars live in `/opt/mopro/.env` on the VDS. They are forwarded to the `grafana-agent` container via `docker-compose.prod.yml`.

| Variable            | Where to find it                        |
|---------------------|-----------------------------------------|
| `GRAFANA_PROM_USER` | Grafana Cloud → Stacks → Prometheus → Details → Username |
| `GRAFANA_PROM_PASS` | Grafana Cloud → Stacks → Prometheus → Details → Generate API token |
| `GRAFANA_LOKI_USER` | Grafana Cloud → Stacks → Loki → Details → Username |
| `GRAFANA_LOKI_PASS` | Grafana Cloud → Stacks → Loki → Details → Generate API token |
| `GRAFANA_TEMPO_USER`| Grafana Cloud → Stacks → Tempo → Details → Username |
| `GRAFANA_TEMPO_PASS`| Grafana Cloud → Stacks → Tempo → Details → Generate API token |

---

## Pipeline 1 — Metrics (Prometheus → Mimir)

**Scrape targets** (every 30 s):

| Job       | Target           | Port |
|-----------|------------------|------|
| core-svc  | `core-svc:9100`  | 9100 |
| fin-svc   | `fin-svc:9101`   | 9101 |
| jobs-svc  | `jobs-svc:9102`  | 9102 |

**External labels added to every series:** `cluster=mopro`, `market=TR`.

**High-cardinality label protection:** `write_relabel_configs` drops `instance_uuid`, `request_id`, `user_id` before push. These belong as structured log fields, not metric labels.

**Cardinality budget:** 10 000 series per service (enforced by `metrics.AssertCardinalityUnder(10_000)` at startup).

**Verify ingestion:**
```bash
# From VDS — curl to Mimir query endpoint
curl -u "${GRAFANA_PROM_USER}:${GRAFANA_PROM_PASS}" \
  "https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/api/v1/query?query=mopro_build_info"
```
Expected: JSON with `status: "success"` and one result per service.

---

## Pipeline 2 — Logs (stdout → Loki)

The Agent uses Docker SD to discover all running containers and ships their stdout/stderr to Loki.

**Stream labels added per log line:**

| Label       | Source                                      |
|-------------|---------------------------------------------|
| `container` | Docker container name                       |
| `service`   | `com.docker.compose.service` label          |

High-cardinality labels (`instance_uuid`, `request_id`, `user_id`) are stripped by `labeldrop` in `relabel_configs`. They appear as structured fields inside the JSON log line, not as Loki stream labels.

**Log format:** JSON (`logx` package uses `slog` with JSON handler). Grafana Loki's JSON parser extracts fields automatically.

**Verify ingestion in Grafana Explore:**
```logql
{service="core-svc"} | json | level="ERROR"
```

---

## Pipeline 3 — Traces (OTLP → Tempo)

Go services export traces via OTLP gRPC to `grafana-agent:4317`. The Agent forwards to Grafana Tempo Cloud.

**Resource attributes on every span:** `service.name`, `deployment.environment`, `market`.

**Sampling rate:** `AlwaysSample` in development, `TraceIDRatioBased(0.1)` (10 %) in production. Override with `OTEL_TRACES_SAMPLER_ARG` env var.

**Config:** `pkg/otelx/init.go`. Endpoint is `OTEL_EXPORTER_OTLP_ENDPOINT` env var (default: `otel-collector:4317` → resolved to `grafana-agent:4317` by Docker Compose).

**Verify ingestion:** In Grafana Explore, switch to Tempo data source, run a trace search by service name `core-svc` or `fin-svc`.

---

## Restarting the Agent

```bash
docker compose -f deploy/docker-compose.prod.yml restart grafana-agent
docker compose -f deploy/docker-compose.prod.yml logs -f grafana-agent
```

If credentials change, update `/opt/mopro/.env` and restart the agent. No service restart needed.

---

## Alert Routing

Grafana Cloud Alerting rules are managed in the Grafana UI. Recommended alerts:

- **service_down**: `absent(mopro_build_info{service="core-svc"})` for 2 m → PagerDuty
- **high_error_rate**: `rate(mopro_http_requests_total{status=~"5.."}[5m]) > 0.05` → Slack
- **cashback_failures**: `increase(mopro_cashback_plan_failures_total[1h]) > 0` → Slack + PD
