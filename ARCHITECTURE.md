# ARCHITECTURE.md — System Topology

This document is the source of truth for the runtime topology. Read before any infrastructure or networking change.

## 1. Bird's-Eye View

```
[ Mobile Flutter app ]
        │ HTTPS
        ▼
[ CloudFlare ]               (CDN + WAF + DDoS + DNS, Free tier)
        │ HTTPS to api.moproshop.com → VDS public IP
        ▼
[ VDS public IP ]            (single 6c/24GB/120GB)
        │ ports 80, 443, <ssh_high_port> only (UFW enforced)
        ▼
[ Caddy 2 ]                  (reverse proxy, TLS, rate limit, JSON access logs)
        │ container DNS
        ├──► core-svc:8080   (HTTP/JSON)
        ├──► fin-svc:8080    (HTTP/JSON, read-only admin endpoints)
        └──► jobs-svc:8080   (HTTP/JSON)
                │
                ▼
[ PgBouncer (transaction mode) ]
        ├──► pgbouncer-ecom:5432   → postgres-ecom:5432   (mopro-net)
        └──► pgbouncer-ledger:5432 → postgres-ledger:5432 (mopro-fin-net)

[ Redis 7 ]        cache + sessions + Streams (event bus)
[ Meilisearch ]    search
[ Backblaze B2 ]   backup target (over Internet)
[ Grafana Cloud ]  logs/metrics/traces (over Internet)
```

## 2. Two Docker Networks

### 2.1 mopro-net (e-commerce side)

Members: `caddy`, `core-svc`, `jobs-svc`, `pgbouncer-ecom`, `postgres-ecom`, `redis`, `meilisearch`, `grafana-agent`. fin-svc also attaches to mopro-net for Redis access only.

### 2.2 mopro-fin-net (FinTech isolation)

Members: `fin-svc`, `pgbouncer-ledger`, `postgres-ledger`.

There is NO TCP path from core-svc or jobs-svc to postgres-ledger. Ledger access is exclusive to fin-svc.

### 2.3 Network rules

- `core-svc` and `jobs-svc` MUST NOT have `mopro-fin-net` membership.
- `fin-svc` is on BOTH `mopro-net` (for Redis) and `mopro-fin-net` (for the ledger DB).
- `postgres-ledger` is on `mopro-fin-net` ONLY.
- When adding a new container, attach to the smallest set of networks. Default is `mopro-net`.

## 3. Three Binaries — Why Not Microservices

### 3.1 The decision

Earlier drafts proposed 12 microservices (one per module). After review, this was changed to **3 binaries** because:

1. **Operational cost.** A 2–3 person team cannot reliably operate 12 deployable units (12 dashboards, 12 build pipelines, 12 alert routes) on a single VDS.
2. **In-process latency.** Within core-svc, modules talk via Go function calls (0 ms). Splitting them adds 5–15 ms HTTP round-trip per inter-module call. The order checkout flow alone makes ~6 inter-module calls; that is 30–90 ms wasted per request.
3. **Debug ergonomics.** A single Go stack trace beats 7 distributed traces every time, especially for a small team.
4. **FinTech isolation preserved.** fin-svc stays separate (its own binary, its own DB, its own network). The compliance argument is intact.

### 3.2 What stayed the same

- Module boundaries (identity, catalog, order, etc.) are unchanged. They are now Go packages instead of binaries.
- DB schema-per-module is unchanged.
- Event-driven communication between core-svc and fin-svc is unchanged.
- The path to true microservices is open: any module is one day's work to extract because boundaries are already enforced by depguard.

### 3.3 What changed

- Inter-module communication inside core-svc became in-memory function calls.
- core-svc → fin-svc communication is the ONLY mandatory async boundary.
- Number of containers dropped from ~16 to ~9.

## 4. Process Layout Inside Each Binary

### 4.1 core-svc

```
core-svc binary
├── HTTP server (Caddy-facing) :8080
├── Metrics server :9090
├── Background workers
│   └── outbox-publisher (only for ecom-side outbox topics)
└── Modules
    ├── identity
    ├── catalog
    ├── cart
    ├── order
    ├── payment
    ├── seller
    └── search
```

### 4.2 fin-svc

```
fin-svc binary
├── HTTP server :8080 (admin / wallet read endpoints)
├── Metrics server :9090
├── Background workers
│   ├── outbox-publisher (Redis Streams XADD from postgres-ledger.outbox)
│   ├── event-consumer  (Redis Streams XREADGROUP for ecom.* topics)
│   └── ledger-reconcile-worker (hourly)
└── Modules
    ├── wallet
    ├── commission
    └── treasury
```

### 4.3 jobs-svc

```
jobs-svc binary
├── HTTP server :8080
├── Metrics server :9090
├── Workers
│   ├── notification-sender
│   ├── support-ai-router
│   └── media-resize-worker
└── Modules
    ├── notification
    ├── support
    ├── media
    └── sizefinder
```

## 5. Data Flow — Order Completion Example

```
1. POST /v1/orders/checkout (mobile) ───► Caddy
2. Caddy ───► core-svc:8080
3. core-svc.order calls core-svc.cart, core-svc.payment (in-memory)
4. core-svc.payment calls PSP (HTTPS egress through CloudFlare)
5. core-svc.order writes orders + outbox row in postgres-ecom (one tx)
6. outbox-publisher XADDs `ecom.order.completed.v1` to Redis Streams
7. fin-svc.commission XREADGROUPs the event
8. fin-svc.commission writes accruals in postgres-ledger
9. (later) settlement job emits `fin.commission.refund.posted.v1`
10. fin-svc.wallet XREADGROUPs that event, writes ledger_entries (D/C) + outbox
11. outbox-publisher emits to Redis Streams; jobs-svc.notification consumes for push.
```

Every step is idempotent. Every event has a `trace_id` linking them in Grafana Tempo.

## 6. Public DNS

| Hostname | Target | Purpose |
|---|---|---|
| `api.moproshop.com` | CloudFlare → VDS | Mobile API |
| `seller.moproshop.com` | CloudFlare → VDS | Seller web panel |
| `img.moproshop.com` | CloudFlare → Backblaze B2 | Public media |

CloudFlare proxy ON (orange cloud) for all three. SSL/TLS mode: Full (strict).

## 7. Failure Domains

| Failure | Blast radius | Mitigation |
|---|---|---|
| One Go module panics | The whole binary it lives in restarts | Health checks, restart policy `unless-stopped` |
| postgres-ecom down | core-svc + jobs-svc broken; fin-svc independent | Restart, restore from B2 |
| postgres-ledger down | fin-svc broken; orders queue in outbox | Restart, restore from B2 |
| redis down | Cache cold + Streams unavailable; events queue in outbox | Restart, AOF replay |
| Caddy down | All ingress lost | Restart |
| Whole VDS down | Everything | Restore on new VDS from B2; RTO 4h |
| Disk full | Postgres halts | Panic mode at 92%: read-only switch (see DISASTER_RECOVERY.md) |

## 8. Communication Path Reference

| From → To | Mechanism | Synchronous? |
|---|---|---|
| Mobile → Caddy | HTTPS (CloudFlare) | Sync |
| Caddy → core-svc | HTTP/JSON | Sync |
| Caddy → fin-svc | HTTP/JSON (admin + wallet read) | Sync |
| Caddy → jobs-svc | HTTP/JSON | Sync |
| core-svc.module → core-svc.module | In-memory function call | Sync |
| core-svc → fin-svc | Redis Streams events | Async (only) |
| core-svc / fin-svc → jobs-svc | HTTP or Redis Streams | Both allowed |
| fin-svc → core-svc | Redis Streams events | Async (only) |
| Any service → Postgres | TCP via PgBouncer | Sync |
| outbox-publisher → Redis | XADD | Sync inside tx of publisher |

## 9. Change Procedure

Any change to this topology (network membership, binary boundaries, DB cluster split) requires:

1. ADR file in `/docs/adr/NNNN-<title>.md` describing decision and consequences.
2. Update of this `ARCHITECTURE.md`.
3. Update of `INFRASTRUCTURE.md` resource budgets if footprint changes.
4. Human approval.
