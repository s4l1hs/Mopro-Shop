# Caddy Path-to-Binary Routing (Authoritative)

This document is the **authoritative source** for which HTTP paths Caddy routes to
which backend binary. All Caddyfile changes must be consistent with this document.
If there is a conflict, this document wins — update the Caddyfile to match, not the
other way around.

---

## DNS

| Hostname | A Record | Purpose |
|---|---|---|
| `api.moproshop.com` | `195.85.207.92` | Primary API entry point (CloudFlare proxied) |
| `fin.moproshop.com` | `195.85.207.92` | Reserved for direct fin-svc access (internal / ops); NOT exposed to mobile clients. CloudFlare proxied. |

CloudFlare is the only allowed path to the VDS. Direct IP access from the public
internet is rejected by Caddy via host header validation.

---

## Routing Table

| Path prefix | Backend binary | Port | Docker service |
|---|---|---|---|
| `/v1/wallet/*` | `fin-svc` | `8081` | `fin-svc` |
| `/v1/cashback/*` | `fin-svc` | `8081` | `fin-svc` |
| `/v1/*` (all other) | `core-svc` | `8080` | `core-svc` |
| `/healthz` | `core-svc` | `8080` | `core-svc` |

`jobs-svc` (port `8082`) does not expose any public HTTP endpoints. It is reachable
internally from `core-svc` and `fin-svc` via Docker internal DNS (`jobs-svc:8082`).

---

## Network Topology

```
Internet
   │
   ▼
CloudFlare (WAF + CDN)
   │
   ▼
Caddy :443 (mopro-net)
   ├─ /v1/wallet/*    ──▶  fin-svc:8081  (mopro-fin-net)
   ├─ /v1/cashback/*  ──▶  fin-svc:8081  (mopro-fin-net)
   └─ /v1/*           ──▶  core-svc:8080 (mopro-net)
```

`fin-svc` sits on both `mopro-net` (Redis access) and `mopro-fin-net` (postgres-ledger +
pgbouncer-ledger). Caddy reaches `fin-svc` via `mopro-net`.

---

## Adding a New Endpoint

1. Add the endpoint to `api/openapi.yaml` under the appropriate tag.
2. If the tag is `wallet` or `cashback`, the endpoint is routed to `fin-svc` automatically
   by the existing wildcard rules. No Caddyfile change needed.
3. If the tag belongs to a new fin-svc domain (not yet wallet/cashback), add a new
   path prefix rule to the Caddyfile AND update this document in the same commit.
4. All other tags route to `core-svc`. No Caddyfile change needed.

---

## Caddyfile Reference

The Caddyfile lives at `deploy/caddy/Caddyfile`. Key routing directives:

```caddy
@fin_routes {
    path /v1/wallet/*
    path /v1/cashback/*
}
reverse_proxy @fin_routes fin-svc:8081

reverse_proxy /v1/* core-svc:8080
reverse_proxy /healthz core-svc:8080
```

Validate after any Caddyfile edit:

```bash
make caddy-validate
make caddy-reload
```

---

*This document is part of the Mopro Shop architecture constitution. Changes require
explicit human approval.*
