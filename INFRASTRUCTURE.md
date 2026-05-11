# INFRASTRUCTURE.md — Resource Limits and Hardening

This file is the contract for what each container is allowed to consume on the single VDS. Violating a limit will likely cause OOM kills and Postgres data corruption.

## 1. VDS Profile

- **Provider:** generic VDS (replaceable).
- **CPU:** 6 vCPU.
- **RAM:** 24 GB.
- **Disk:** 120 GB SSD (NVMe preferred).
- **Network:** 1 Gbps unmetered.
- **Cost:** 940 TL/month.
- **OS:** Ubuntu 22.04 LTS or Debian 12.

## 2. RAM Budget — TOTAL = 24 GB

| Container | mem_limit | mem_reservation | cpus | shm_size | Notes |
|---|---|---|---|---|---|
| postgres-ecom | 5g | 3g | 2.0 | 256m | shared_buffers 2g, effective_cache_size 6g |
| postgres-ledger | 3g | 2g | 1.5 | 128m | shared_buffers 1g, effective_cache_size 3g |
| redis | 1.2g | — | 1.0 | — | redis.conf maxmemory 800mb |
| meilisearch | 1.5g | — | 1.0 | — | |
| pgbouncer-ecom | 100m | — | 0.2 | — | |
| pgbouncer-ledger | 100m | — | 0.2 | — | |
| caddy | 256m | — | 0.5 | — | |
| core-svc | 384m | 192m | 0.5 | — | go-defaults |
| fin-svc | 384m | 192m | 0.5 | — | go-defaults |
| jobs-svc | 384m | 192m | 0.5 | — | go-defaults |
| grafana-agent | 300m | — | 0.3 | — | |

**Hard limit total: ~12.6 GB.**
**Reserved for OS + Linux page cache: ~11 GB. CRITICAL — Postgres performance depends on this.**

### 2.1 Why the page cache headroom matters

- Postgres reads pass through the kernel's page cache.
- With ~11 GB free, ~6–8 GB of working set stays hot.
- Without the headroom, Postgres falls back to disk; latency spikes; OOM Killer becomes a risk.
- DO NOT raise mem_limit values to "use available RAM". The headroom IS the design.

## 3. CPU Budget — TOTAL = 6 vCPU

Sum of `cpus` across containers ≈ 8.4 (over-commit by ~40%, intentional). On normal load, average CPU is 35–50%; peaks reach 70–80%. CPU shares are fair, so heavy Postgres queries cannot starve Caddy or the Go binaries.

## 4. PIDs and Ulimits

Every Go binary container:

```yaml
pids_limit: 256
ulimits:
  nofile: { soft: 4096, hard: 8192 }
```

This blocks fork bombs and limits file descriptor exhaustion.

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

postgres-ecom and postgres-ledger keep `read_only: false` because they need to write to the data volume. They still get `cap_drop` (except IPC_LOCK if needed), `no-new-privileges`, and resource limits.

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
  cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID]   # minimum needed for postgres init
```

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

NO direct exposure of Postgres, Redis, Meilisearch, or any service port. They are only reachable inside Docker networks.

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

The system reboots at 03:30 if a kernel patch is available. Container `restart: unless-stopped` brings everything back. After first install, perform a manual test reboot to confirm clean recovery.

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

## 8. Image Build Rules

- Base for runtime: `gcr.io/distroless/static-debian12:nonroot` ONLY.
- Multi-stage: builder stage uses `golang:1.22-alpine`; final stage copies the binary.
- `CGO_ENABLED=0` always (static binary).
- Image MUST be < 25 MB.
- Tag scheme: `ghcr.io/mopro/<binary>:<semver>` plus `:git-<sha>`. Production manifests use `@sha256:<digest>`, never tags.

## 9. Grafana Agent — Telemetry Standard

`/opt/mopro/grafana-agent/agent.yaml` collects metrics, logs, traces and ships to Grafana Cloud (free tier).

```yaml
server: { log_level: info }

metrics:
  global:
    scrape_interval: 30s
    external_labels: { cluster: mopro-prod }
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
        - url: https://logs-prod-XX.grafana.net/loki/api/v1/push
          basic_auth: { username: ${GRAFANA_LOKI_USER}, password: ${GRAFANA_LOKI_PASS} }
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
| `module` | string | `identity` / `wallet` / etc. |
| `trace_id` | string | always present in HTTP-handling code |
| `span_id` | string | when inside an active span |
| `msg` | string | human message |
| `err` | string | only on errors |

PII is NEVER logged. Hash if needed for joining.

### 9.2 Metric naming

`mopro_<service>_<module>_<metric>{labels}`.

Examples:
- `mopro_core_order_checkout_duration_seconds_bucket`
- `mopro_fin_wallet_balance_query_total`
- `mopro_jobs_notification_send_failed_total`

## 10. Resource Verification

Before any change to limits, run:

```bash
docker stats --no-stream
docker compose ps
df -h /
free -h
```

If the change increases any limit, prove the headroom (Postgres pages + OS) is unaffected. Otherwise reject.
