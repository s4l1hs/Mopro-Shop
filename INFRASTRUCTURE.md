# INFRASTRUCTURE.md — Resource Limits and Hardening v7

This file is the contract for what each container is allowed to consume on the single VDS. Violating a limit will likely cause OOM kills and Postgres data corruption.

Reflects PRD v6.0 (perpetual cashback) + v7 detail packs (PSP & kargo API'ları, mobil 30+ ekran, anti-fraud ML, TR e-fatura/e-arşiv/GİB).

---

## 1. VDS Profile

- **Provider:** generic VDS (replaceable; e.g., a TR-based provider for launch).
- **CPU:** 6 vCPU.
- **RAM:** 24 GB.
- **Disk:** 120 GB SSD (NVMe preferred).
- **Network:** 1 Gbps unmetered.
- **Cost:** ~30 USD/month equivalent (940 TL at TR provider as of May 2026; comparable to Hetzner CCX13 EU).
- **OS:** Ubuntu 22.04 LTS or Debian 12.

---

## 2. RAM Budget — TOTAL = 24 GB

| Container | mem_limit | mem_reservation | cpus | shm_size | Notes |
|---|---|---|---|---|---|
| postgres-ecom | 5g | 3g | 2.0 | 256m | shared_buffers 2g, effective_cache_size 6g |
| postgres-ledger | 3g | 2g | 1.5 | 128m | shared_buffers 1g, effective_cache_size 3g |
| redis | 1.2g | — | 1.0 | — | maxmemory 800mb |
| meilisearch | 1.5g | — | 1.0 | — | TR, EN, DE, AR-aware |
| pgbouncer-ecom | 100m | — | 0.2 | — | |
| pgbouncer-ledger | 100m | — | 0.2 | — | |
| caddy | 256m | — | 0.5 | — | |
| core-svc | 384m | 192m | 0.5 | — | go-defaults |
| fin-svc | 384m | 192m | 0.5 | — | go-defaults; cashback engine + seller-payout engine in-process |
| jobs-svc | 1.2g | 384m | 0.8 | — | v7: ML inference (NLP+vision ONNX) + e-fatura XML processing — ÜST sınır arttırıldı |
| grafana-agent | 300m | — | 0.3 | — | |

**Hard limit total: ~13.4 GB (v7).**
**Reserved for OS + Linux page cache: ~10.5 GB. CRITICAL — Postgres performance depends on this.**

### 2.0 v7 Eklemeleri — jobs-svc neden büyüdü?

v7 itibarıyla jobs-svc içinde 2 yeni iş yükü çalışıyor:

**Anti-fraud ML inference:** ONNX runtime + 2 model dosyası (NLP ~440 MB + Vision ~25 MB) bellekte tutulur. Inference per request:
- NLP (BERT-tr): ~250 MB peak, 200ms p95 CPU
- Vision (EfficientNet-b0): ~150 MB peak, 150ms p95 CPU
- Bellekte ortalama yer: 600-700 MB (modeller + 5-10 paralel inference)

**e-Fatura XML processing:** Foriba'ya göndermeden önce UBL-TR XML render + xmllint XSD validation. Per invoice:
- XML render + sign: ~5 MB peak
- 100 invoice/dakika throughput rahat

Toplam jobs-svc tipik kullanım: ~700-900 MB. Mem_limit 1.2 GB güvenli buffer bırakır. OOM olduğunda restart safe (cron tekrar dener).

**Eğer ML modelleri çok büyürse (>1 GB toplam):** jobs-svc'yi 2'ye böl — `jobs-light-svc` (notification, support, media, e-fatura) + `jobs-ml-svc` (anti-fraud, sizefinder). Bu Phase 8+ kararı; o noktada da 2. VDS de devreye girmiş olur.

### 2.1 Why the page cache headroom matters

- Postgres reads pass through the kernel's page cache.
- With ~11 GB free, ~6–8 GB of working set stays hot.
- Without the headroom, Postgres falls back to disk; latency spikes; OOM Killer becomes a risk.
- DO NOT raise mem_limit values to "use available RAM". The headroom IS the design.

### 2.2 fin-svc Memory Footprint (with both cashback + seller payout engines)

The cashback monthly cron processes scheduled payments in batches of 1000. Each batch:
- Loads ~1000 payment rows + 1000 plan rows (~500 KB)
- Opens 1000 SQL transactions (one per payment) inside fin-svc
- Peak memory during run: ~50 MB extra (negligible vs. 384 MB limit)

The seller payout daily cron processes scheduled payouts in batches of 1000. Each batch:
- Loads ~1000 payout rows (~150 KB)
- Calls PSP transfer API per payout (HTTPS round-trip ~150 ms each, mostly I/O wait)
- Peak memory during run: ~30 MB extra
- Throughput goal: 1000 payouts in < 5 minutes (well within the 30-minute window before next cron)

For 10K active plans, the cashback cron completes in < 30 seconds. For 1M active plans (future scale), batching + parallel workers needed (reserved for Phase 8+).

For 100 daily payouts, the seller payout cron completes in < 1 minute. For 10K daily payouts (≈1M TL/day GMV scale), parallel PSP transfer with bounded concurrency is needed (Phase 7+).

---

## 3. CPU Budget — TOTAL = 6 vCPU

Sum of `cpus` across containers ≈ 8.4 (over-commit by ~40%, intentional). On normal load, average CPU is 35–50%; peaks reach 70–80%. CPU shares are fair, so heavy Postgres queries cannot starve Caddy or the Go binaries.

Cron CPU spikes (no impact on user-facing latency, all run outside business hours):
- Cashback monthly cron: 1st of month at 02:00 UTC. CPU spikes for ~30 seconds.
- Seller payout daily cron: every day at 02:30 UTC. CPU spikes for ~1 minute.
- Treasury monitor: every day at 03:00 UTC. < 5 seconds.
- Ledger reconcile (per-currency): every hour at :05. < 2 seconds.
- Balance MV refresh: every hour at :15. < 5 seconds.

---

## 4. PIDs and Ulimits

Every Go binary container:

```yaml
pids_limit: 256
ulimits:
  nofile: { soft: 4096, hard: 8192 }
```

This blocks fork bombs and limits file descriptor exhaustion.

---

## 5. Container Hardening — MANDATORY for every Go binary

```yaml
x-go-defaults: &go-defaults
  restart: unless-stopped
  mem_limit: 384m
  mem_reservation: 192m
  cpus: '0.5'
  pids_limit: 256
  security_opt:
    - no-new-privileges:true
  cap_drop: [ALL]
  read_only: true
  tmpfs:
    - /tmp:size=64M,mode=1777
  ulimits:
    nofile: { soft: 4096, hard: 8192 }
  logging:
    driver: json-file
    options: { max-size: "20m", max-file: "5" }
  networks: [ mopro-net ]
```

### 5.1 Why each flag

- `no-new-privileges`: blocks setuid escalation inside the container.
- `cap_drop: [ALL]`: container has zero Linux capabilities. Go binaries don't need any.
- `read_only: true`: filesystem is RO; an attacker cannot drop a payload.
- `tmpfs /tmp`: the only writable area, in RAM, capped at 64 MB.
- `pids_limit`: cap on processes/threads.
- `mem_limit`: hard ceiling. Container is OOM-killed and restarted; nothing else suffers.

### 5.2 Postgres exception

postgres-ecom and postgres-ledger keep `read_only: false` because they need to write to the data volume. They still get `cap_drop`, `no-new-privileges`, and resource limits.

```yaml
postgres-ecom:
  mem_limit: 5g
  mem_reservation: 3g
  cpus: '2.0'
  shm_size: 256m
  read_only: false
  security_opt:
    - no-new-privileges:true
  cap_drop: [ALL]
  cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID]
```

---

## 6. Networking

Two Docker networks (see `ARCHITECTURE.md` § 2):

```yaml
networks:
  mopro-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24
  mopro-fin-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.31.0.0/24
```

Public ports (host firewall, UFW):

```bash
ufw default deny incoming
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 58022/tcp comment 'SSH non-default'
ufw enable
```

NO direct exposure of Postgres, Redis, Meilisearch, or any service port.

---

## 7. Kernel and OS Hardening

### 7.1 unattended-upgrades — MANDATORY

```bash
apt-get install -y unattended-upgrades apt-listchanges

# /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:30";

# /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
```

Note: 03:30 UTC reboot time. Cashback cron runs at 02:00 UTC, seller payout cron at 02:30 UTC, so the reboot does not interfere.

### 7.2 SSH

```text
# /etc/ssh/sshd_config
Port 58022
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers deploy
```

`fail2ban` protects this port automatically.

### 7.3 Userns-remap (Docker daemon)

```json
// /etc/docker/daemon.json
{
  "userns-remap": "default",
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "5" },
  "no-new-privileges": true
}
```

After enabling userns-remap, fix ownership of bind-mount directories under `/opt/mopro/data/` to the remapped UID range. Test in staging first.

---

## 8. Image Build Rules

- Base for runtime: `gcr.io/distroless/static-debian12:nonroot` ONLY.
- Multi-stage: builder stage uses `golang:1.22-alpine`; final stage copies the binary.
- `CGO_ENABLED=0` always (static binary).
- Image MUST be < 25 MB.
- Tag scheme: `ghcr.io/mopro/<binary>:<semver>` plus `:git-<sha>`. Production manifests use `@sha256:<digest>`, never tags.

---

## 9. Grafana Agent — Telemetry Standard

`/opt/mopro/grafana-agent/agent.yaml` collects metrics, logs, traces and ships to Grafana Cloud (free tier).

```yaml
server: { log_level: info }

metrics:
  global:
    scrape_interval: 30s
    external_labels:
      cluster: mopro-prod
      market: ${MARKET}             # 'TR' for launch
  configs:
    - name: integrations
      remote_write:
        - url: https://prometheus-prod-XX.grafana.net/api/prom/push
          basic_auth:
            username: ${GRAFANA_PROM_USER}
            password: ${GRAFANA_PROM_PASS}
      scrape_configs:
        - job_name: docker
          docker_sd_configs:
            - host: unix:///var/run/docker.sock

logs:
  configs:
    - name: docker-logs
      clients:
        - url: https://logs-prod-XX.grafana.net/loki/api/push
          basic_auth: { username: ${GRAFANA_LOKI_USER}, password: ${GRAFANA_LOKI_PASS} }
          external_labels:
            market: ${MARKET}
      scrape_configs:
        - job_name: docker
          docker_sd_configs:
            - host: unix:///var/run/docker.sock

traces:
  configs:
    - name: tempo
      remote_write:
        - endpoint: tempo-XX.grafana.net:443
          basic_auth: { username: ${GRAFANA_TEMPO_USER}, password: ${GRAFANA_TEMPO_PASS} }
      receivers:
        otlp:
          protocols:
            grpc: { endpoint: 0.0.0.0:4317 }
```

### 9.1 Application logging contract

Every log line written by Go binaries MUST be JSON with these fields:

| Field | Type | Notes |
|---|---|---|
| `time` | RFC3339 string | UTC |
| `level` | string | debug / info / warn / error |
| `service` | string | `core-svc` / `fin-svc` / `jobs-svc` |
| `module` | string | `identity` / `wallet` / `cashback` / `sellerpayout` / etc. |
| `market` | string | from `MARKET` env (TR launch) |
| `currency` | string | when applicable to the operation |
| `trace_id` | string | always present in HTTP-handling code |
| `span_id` | string | when inside an active span |
| `msg` | string | human message |
| `err` | string | only on errors |

PII is NEVER logged. Hash if needed for joining.

### 9.2 Metric naming

`mopro_<service>_<module>_<metric>{labels}`.

Mandatory labels on EVERY metric:
- `market` (e.g., `"TR"`)

Conditional labels (when applicable):
- `currency` (e.g., `"TRY"`, `"TRY_COIN"`)
- `psp_provider` (for payment metrics)
- `category_id` (for commission metrics)
- `coin_jurisdiction` (when COIN_LICENSE_JURISDICTION is set)

Examples:
- `mopro_core_order_checkout_duration_seconds_bucket{market="TR", currency="TRY"}`
- `mopro_fin_wallet_balance_query_total{market="TR", currency="TRY_COIN"}`
- `mopro_fin_cashback_payment_total{market="TR", currency="TRY_COIN", status="paid"}`
- `mopro_fin_cashback_payment_total{market="TR", currency="TRY_COIN", status="failed"}`
- `mopro_fin_sellerpayout_total{market="TR", currency="TRY", status="paid"}`
- `mopro_fin_sellerpayout_total{market="TR", currency="TRY", status="failed"}`
- `mopro_fin_sellerpayout_lag_business_days{market="TR"}` (should always be ~3)
- `mopro_jobs_notification_send_failed_total{market="TR", channel="push"}`

### 9.3 Cashback + Seller Payout Dashboards

Two dedicated Grafana dashboards:

**Cashback dashboard:**
- Active plans count (gauge)
- Plans created in last 24h (counter)
- Monthly payments due in next 7 days (gauge)
- Last cron run status + duration
- Failed payments count (alert if > 0)
- Total `equity:cashback_distribution:TRY_COIN` balance (gauge; growth trajectory)

**Seller Payout dashboard:**
- Scheduled payouts count (gauge)
- Payouts due today (gauge)
- Last cron run status + duration
- Failed payouts count (alert if > 0)
- Average payout latency (delivered_at → paid_at) — should be ~3 BD
- PSP transfer success rate per provider
- Total `liability:seller_payable:TRY` balance (gauge)

**Treasury dashboard (v6):**
- Real interest rate (TR Merkez Bankası) vs frozen reference (5000 bps = %50)
- Spread per active cohort (real_rate - reference_rate × commission_principal_sum)
- 3-business-day delay float pool size
- Permanent commission capital growth: `equity:retained_commission:TRY` (Mopro's principal — never drawn down)
- Monthly cashback distribution outflow: `Σ cashback_distribution` per period

---

## 10. Resource Verification

Before any change to limits, run:

```bash
docker stats --no-stream
docker compose ps
df -h /
free -h
```

If the change increases any limit, prove the headroom (Postgres pages + OS) is unaffected. Otherwise reject.

---

## 11. Disk Usage Projections (with Cashback Plans + Seller Payouts)

The cashback engine adds significant rows: 1 plan + 24 payment rows per delivered order. The seller payout engine adds 1 payout row per (order, seller) tuple.

| Active orders | Plan rows | Payment rows (24/plan) | Payout rows | Storage estimate |
|---|---|---|---|---|
| 10K | 10K | 240K | 10–20K | ~80 MB |
| 100K | 100K | 2.4M | 100–200K | ~800 MB |
| 1M | 1M | 24M | 1–2M | ~8 GB |

`postgres-ledger` disk projection in `cashback_schema` becomes the dominant grower; `commission_schema.seller_payouts` is much smaller. Plan archival policy NOT applicable in v6 (perpetual); cancellation triggers archival to a separate "cancelled_plans" table after 1-year cool-off.

See `DISASTER_RECOVERY.md` § Disk for thresholds.

---

**End of INFRASTRUCTURE.md.** See ARCHITECTURE.md for topology, DATA_DICTIONARY.md for schemas.
