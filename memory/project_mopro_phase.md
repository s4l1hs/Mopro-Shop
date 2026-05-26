---
name: project-mopro-phase
description: Current phase progress for Mopro Shop — completed prompts, structural decisions, next step
metadata:
  type: project
---

## Current State: L9 complete (pre-cutover smoke infrastructure ready)

**Last completed:** L9 — Cumulative smoke pass infrastructure (launch dress rehearsal)

### Phase progress summary

| Phase | Status |
|-------|--------|
| L4a — Grafana Agent / Healthchecks.io wiring | ✅ Done |
| L4b — Grafana dashboards + alert rules + runbooks | ✅ Done |
| L9 — Smoke infrastructure | ✅ Done |

### L4b deliverables (completed)
- `deploy/grafana/dashboards/` — 4 dashboard JSON files (slo-overview, financial-health, infra-health, backup-cron-health)
- `deploy/grafana/alerts/` — 3 alert rule YAML files (critical.yaml, warning.yaml, info.yaml)
- `deploy/grafana/notification-policy.yaml` — routing critical→PD+BetterStack, warning→Slack, panic→#mopro-panic
- `deploy/grafana/provision.sh` + `make grafana-deploy`
- `docs/runbooks/` — 12 runbooks, one per alert
- `docs/ops/slos.md` — 8 SLI definitions
- `pkg/metrics/job_status.go` — `mopro_job_last_run_status` + `mopro_job_last_run_timestamp_seconds`
- `pkg/metrics/pool.go` — pgxPoolCollector → `mopro_pgx_pool_*` metrics
- `cmd/fin-svc/main.go` — jobPinger wrapper + `--run-once --cron=<name>` flag

### L9 deliverables (completed)
- `cmd/core-svc/version_handler.go` — `GET /__version` → `{service, sha, version, go_version, built_at}`
- `cmd/core-svc/main.go` — registered `GET /__version` at line 320
- `deploy/caddy/Caddyfile` — added `api-staging.moproshop.com` + `staging.moproshop.com` blocks
- `scripts/smoke/run.sh` — 25+ endpoint checks, 9 sections, PASS/STUB/FAIL output
- `scripts/loadtest/k6-smoke.js` — ramping-VU browse + checkout scenario, SLO thresholds
- `scripts/smoke/manual-handoff.md` — 11-section manual UI checklist
- `docs/launch/L9-smoke-report-TEMPLATE.md` — fill-in-the-blanks smoke report
- `Makefile` — added `build-all`, `deploy-staging`, `smoke`, `loadtest` targets + `FORCE=1` support for seed-staging

### Key architectural decisions locked in
- Reconcile cron lives in **fin-svc**, not jobs-svc: `fin-svc --run-once --cron=ledger-reconcile-weekly`
- Post-load reconcile SQL: query `wallet_schema.ledger_alerts WHERE resolved_at IS NULL`
- OTP bypass for staging: `DEV_OTP_ACCEPT_ANY=true` (already in identity/service.go)
- Cart payload: `{"variant_id": <id>, "qty": 1}` (not product_id)
- Cart reserve → `POST /cart/reserve` returns `{"reservation_id": "...", "expires_at": "..."}`
- Checkout: needs `reservation_id` from reserve step + `Idempotency-Key` header
- Fin-svc routes accessible via Caddy: `/wallet/*` `/cashback/*` → fin-svc:8081
- Profile endpoint: `GET /me` (not `/profile`)

**Why:** L9 is the launch dress rehearsal. These notes prevent re-deriving architecture
when answering future questions about smoke, deploy, or staging setup.

**How to apply:** When user asks about staging, deployment, or smoke testing,
use these confirmed endpoint paths and command patterns.
