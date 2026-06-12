# Mopro VDS Runbook

**Server:** 195.85.207.92 | **OS:** Debian 13 (trixie) | **SSH:** port 4625, user `mopro`  
**Services:** core-svc · fin-svc · jobs-svc · caddy · postgres-ecom · postgres-ledger · postgres-config · redis · pgbouncer-ecom · pgbouncer-ledger · grafana-agent  
**Deploy pattern:** `deploy` GitHub workflow → GHCR pull (`ghcr.io/s4l1hs/*`) → `up -d` + image-ID assertion (legacy tarball path retired — F-DH-RESIDUAL)

---

## SSH access

```sh
ssh -p 4625 mopro@195.85.207.92
```

Copy a file to VDS:
```sh
scp -P 4625 <local-file> mopro@195.85.207.92:/opt/mopro/
```

---

## Day 0 — First production deploy

### Prerequisites

1. VDS is up with Debian 13 and user `mopro` exists, sshd on port 4625.
2. Run bootstrap (as root on VDS):
   ```sh
   # Upload script from dev machine first:
   scp -P 4625 deploy/setup-server.sh mopro@195.85.207.92:/tmp/
   ssh -p 4625 mopro@195.85.207.92 "sudo bash /tmp/setup-server.sh"
   ```
3. Populate secrets (on VDS as root):
   ```sh
   sudo bash /opt/mopro/deploy/scripts/init-secrets.sh
   ```
4. Add the generated Hetzner backup SSH key to your Storage Box `authorized_keys`.

### First deploy

Dispatch the **`deploy` GitHub workflow** (`workflow_dispatch`, `verify_only=false`).
It scps a fresh `docker-compose.prod.yml` + `deploy_script.sh` to the host, logs into
GHCR, pulls `ghcr.io/s4l1hs/*`, `up -d`, waits on `/healthz`, and **asserts the running
image == the pulled ref**. Prereq: `GHCR_USER`/`GHCR_PAT` in the host `.env` (docs/deploy.md).
(The legacy `make deploy` tarball path is retired — F-DH-RESIDUAL.)

### Install systemd backup timer (on VDS as root)

```sh
cp /opt/mopro/deploy/systemd/mopro-backup.{service,timer} /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now mopro-backup.timer
systemctl status mopro-backup.timer
```

### Verify

```sh
curl -sf https://api.moproshop.com/healthz      # → OK
curl -sf https://seller.moproshop.com/healthz   # → OK
ssh -p 4625 mopro@195.85.207.92 "docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

---

## Routine operations

### TLS / ACME renewal health (F-DH-3)

The Caddy service carries `dns: [1.1.1.1, 8.8.8.8, 9.9.9.9]` — the host's single
upstream resolver (8.8.8.8) had SERVFAIL episodes that broke ACME-endpoint lookups
(`lookup acme-v02.… on 127.0.0.11:53: server misbehaving`). Check renewal health:

```sh
# Failures (want: none recent) vs successes (want: steady stream)
ssh -p 4625 mopro@195.85.207.92 "docker logs caddy --since 168h 2>&1 | grep -c 'server misbehaving'"
ssh -p 4625 mopro@195.85.207.92 "docker logs caddy --since 168h 2>&1 | grep -c 'got renewal info'"
# Cert expiry per domain (earliest currently 2026-08-18; renewal window opens ~Jul 19)
echo | openssl s_client -connect api.moproshop.com:443 -servername api.moproshop.com 2>/dev/null \
  | openssl x509 -noout -enddate
```

Applying a compose-level change to caddy = container **recreate** (`docker compose
-f docker-compose.prod.yml up -d caddy`, ~2–5 s listener blip, cert state persists
in `caddy-data`) — `caddy reload` only re-reads the Caddyfile. Always
`caddy validate` first. Staging-CA test procedure (no rate-limit exposure):
`docs/internal/f-dh-3-caddy-acme.md` §6.

### Check container health

```sh
ssh -p 4625 mopro@195.85.207.92 "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.RunningFor}}'"
```

### View logs

```sh
ssh -p 4625 mopro@195.85.207.92 "docker logs --tail 100 -f core-svc"
ssh -p 4625 mopro@195.85.207.92 "docker logs --tail 100 -f fin-svc"
ssh -p 4625 mopro@195.85.207.92 "docker logs --tail 100 -f jobs-svc"
ssh -p 4625 mopro@195.85.207.92 "docker logs --tail 100 -f caddy"
```

### Deploy a new version

Dispatch the **`deploy` GitHub workflow** (Actions → deploy → run, `verify_only=false`).
Fail-fast: a denied pull, failed login, unhealthy service, or image-ID mismatch exits
non-zero — a green run means the new images are live.

### Rollback manually

GHCR keeps a `:<full-sha>` tag per main build (`build-images.yml`), so rollback =
re-run the previous build pinned by tag, on-host:

```sh
ssh -p 4625 mopro@195.85.207.92
sudo env IMAGE_NS=s4l1hs VERSION=<previous-full-sha> \
  docker compose -f /opt/mopro/deploy/docker-compose.prod.yml up -d core-svc fin-svc jobs-svc
curl -s http://127.0.0.1:8080/__version   # confirm the rolled-back SHA
```

(The tarball-based `make rollback` / `bin/prev/` path is retired — F-DH-RESIDUAL.
DEFER: a `version` input on the deploy workflow to make rollback a dispatch too.)

### Post-flip cleanup: purge stale `mopro/*` images (one-time, gated)

Once a real deploy has flipped prod onto `ghcr.io/s4l1hs/*` (verify first line below
shows only ghcr refs for the three services), the legacy local images + tarballs can go:

```sh
sudo docker ps --format '{{.Names}}\t{{.Image}}' | grep -E 'core-svc|fin-svc|jobs-svc'
# ALL three must show ghcr.io/s4l1hs/* — if ANY shows mopro/*, STOP (deploy gap).
sudo docker image ls --format '{{.Repository}}:{{.Tag}}' | grep '^mopro/' \
  | xargs -r -n1 sudo docker image rm     # refuses in-use images — that's the guard
rm -rf /opt/mopro/bin/*.tar /opt/mopro/bin/prev/
```

Never `docker system prune` / `image prune -a`; never touch `ghcr.io/*`, volumes, networks.

### Apply a database migration

```sh
./deploy/scripts/apply-migration.sh \
  --db ecom \
  --file deploy/postgres-ecom/init/99-new-migration.sql
```

Tracks applied migrations in `_migrations` table. Safe to re-run (idempotent by name).

### Reload Caddy config (without restart)

```sh
ssh -p 4625 mopro@195.85.207.92 \
  "docker exec caddy caddy reload --config /etc/caddy/Caddyfile"
```

---

## Backup & Restore

### Manual backup trigger

```sh
ssh -p 4625 mopro@195.85.207.92 "sudo systemctl start mopro-backup.service"
journalctl -u mopro-backup.service --no-pager | tail -30
```

### Verify backup timer

```sh
ssh -p 4625 mopro@195.85.207.92 "systemctl list-timers mopro-backup.timer"
```

### List available backups

```sh
ssh -p 4625 mopro@195.85.207.92 "ls -lh /opt/mopro/backups/"
```

### Restore ecom database

```sh
ssh -p 4625 mopro@195.85.207.92
# On VDS:
sudo bash /opt/mopro/deploy/scripts/restore-postgres.sh \
  --db ecom \
  --date 2026-05-20T040000Z \
  --confirm YES
```

### Restore ledger database

```sh
sudo bash /opt/mopro/deploy/scripts/restore-postgres.sh \
  --db ledger \
  --date 2026-05-20T040000Z \
  --confirm YES
```

**WARNING:** Restore stops dependent services, overwrites all data, then restarts services. Verify ledger invariants after restore:

```sh
docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger \
  -c "SELECT SUM(CASE WHEN direction='D' THEN amount_minor ELSE -amount_minor END) FROM wallet_schema.ledger_entries;"
# Must be 0 (balanced ledger)
```

---

## Incident response

### Service down

```sh
# Check status
docker inspect --format='{{.State.Status}} {{.State.Health.Status}}' core-svc

# Restart a single service
ssh -p 4625 mopro@195.85.207.92 \
  "cd /opt/mopro && docker compose -f docker-compose.prod.yml restart core-svc"

# Check logs for crash reason
ssh -p 4625 mopro@195.85.207.92 "docker logs --tail 200 core-svc 2>&1 | grep -i error"
```

### Disk full

```sh
ssh -p 4625 mopro@195.85.207.92 "df -h && du -sh /opt/mopro/*"

# Clear old Docker images
ssh -p 4625 mopro@195.85.207.92 "docker image prune -f"

# Clear old logs
ssh -p 4625 mopro@195.85.207.92 "docker system df"
```

### PgBouncer connection exhausted

Check: `docker logs pgbouncer-ecom | grep "too many clients"`.  
Mitigation: restart PgBouncer (zero-downtime — Postgres keeps connections):

```sh
ssh -p 4625 mopro@195.85.207.92 \
  "docker compose -f /opt/mopro/docker-compose.prod.yml restart pgbouncer-ecom"
```

### Redis OOM

Redis is configured with `maxmemory 800m` and `maxmemory-policy allkeys-lru`. If it OOMs, check:

```sh
ssh -p 4625 mopro@195.85.207.92 "docker exec redis redis-cli INFO memory | grep used_memory_human"
```

---

## Known quirks

| Quirk | Explanation |
|---|---|
| SSH port 4625 | Custom port — never use 22 in any SSH/SCP command for this VDS |
| Hetzner Storage Box SSH port 23 | Hetzner uses port 23 (not 22) for Storage Box SFTP/rsync |
| UFW uses nftables backend | Debian 13 default; inspect rules with `nft list ruleset` not `iptables -L` |
| Caddy pinned `2.8-alpine` | Do NOT use `caddy:2-alpine` (unpinned); breaking changes in minor versions |
| GHCR pull deploys | Images pull from `ghcr.io/s4l1hs/*` (private — `GHCR_USER`/`GHCR_PAT` in host `.env`); the old tarball/`docker load` path is retired |
| Host DNS | `/etc/resolv.conf` carries multiple nameservers (8.8.8.8 + 1.1.1.1 + 9.9.9.9) — single-resolver SERVFAIL broke ACME lookups (F-DH-3/RESIDUAL). A `dhclient` runs but does not manage the file; if that ever changes, use `supersede domain-name-servers` in `/etc/dhcp/dhclient.conf` |
| fin-svc dual-homed | fin-svc is on both `mopro-net` (Redis) and `mopro-fin-net` (postgres-ledger) |
| postgres-config stub | Empty cluster, no services connect to it in Phase 4.0.5 |
| Secrets at `/etc/mopro/.env` | chmod 600 root:root; `/opt/mopro/.env` is a symlink to this file |
| Healthcheck: `["/svc", "--health"]` | Distroless containers have no shell/nc; binary must implement `--health` flag |
