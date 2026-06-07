# F-DH-3 Discovery — Caddy ACME-Renewal DNS Errors (§2)

> Evidence-driven root-cause for the ACME errors filed in `docs/audits/PRODUCTION_DEPLOY_HEALTH.md`
> §6/F-DH-3 (PR #104). Live host + repo source; date 2026-06-07. 30-day log window.

## 1. Topology + config (§2.1)

- **Caddy:** `caddy:2.8-alpine` (stock — no DNS-provider modules compiled in), config
  `deploy/caddy/Caddyfile`, ACME email via `{$CADDY_EMAIL}` (key present in host `.env` ✓).
- **Challenge type: HTTP-01 / TLS-ALPN-01 defaults** (no `tls dns …` anywhere). Ports 80/443/443-udp
  published; public reachability proven (PR #104: public `/healthz` 200, valid LE cert).
- **`/data` + `/config` ARE persisted** as named volumes `caddy-data`/`caddy-config`
  (`mopro.keep: "true"`) — **discovery shift vs. the prompt's "classic cause" candidate**: no
  re-issue storms; ACME account + cert state survive restarts. Confirmed live: 8 LE certs + the
  internal CA present under `/data/caddy/certificates/`.
- **Served domains (LE-managed, = the cert-backstop watchlist):**
  `api` · `seller` · `moproshop.com` · `www` · `admin` · `fin` · `api-staging` · `staging`
  (.moproshop.com), plus `api.localhost`/`seller.localhost` on the internal CA (12-hour certs —
  their constant renewal explains the 88 "renewing certificate" log lines; normal churn, not LE).
- **CA endpoint:** default issuer chain (Let's Encrypt prod, ZeroSSL fallback). All real certs were
  issued by `acme-v02.api.letsencrypt.org-directory`.

## 2. The actual error (§2.2) — quoted

Latest representative line (same family as the 512 errors over 30 d):

```json
{"level":"warn","ts":1780834872.61,"logger":"tls.issuance.acme.acme_client",
 "msg":"HTTP request failed; retrying","url":"https://acme.zerossl.com/v2/DV90",
 "error":"performing request: Get \"https://acme.zerossl.com/v2/DV90\":
          dial tcp: lookup acme.zerossl.com on 127.0.0.11:53: server misbehaving"}
```

and the LE variant (PR #104 §6): `lookup acme-v02.api.letsencrypt.org on 127.0.0.11:53: server misbehaving`.

**Classification: outbound DNS resolution failure** from inside the Caddy container — neither a
DNS-01 provider/credential issue (no DNS-01 in use), nor HTTP-01 reachability (inbound is fine),
nor rate-limit, nor storage/persistence. `127.0.0.11` is Docker's embedded DNS, which forwards
external queries to the host's resolvers; "server misbehaving" = SERVFAIL/timeout from upstream.

**Frequency / shape (30 d):**

| signal | count |
|---|---|
| `server misbehaving` errors by day | **402 on 06-01, 94 on 06-02**, 3 · 13 · 1 · 5 thereafter |
| ARI refresh: got renewal info / failed (30 d) | 451 / 182 (~71 % ok) |
| ARI refresh last 72 h | **94 ok / 2 fail (~98 %)** |
| `HTTP request failed; retrying` | 407 — Caddy retries; refreshes eventually succeed |

Secondary log families, both **benign noise** (no action):
- `HTTP 404 …unauthorized - Issuer not found` ×71 — ZeroSSL ARI lookups for LE-issued certs
  (Caddy 2.8 dual-issuer default); harmless.
- `no information found to solve challenge for identifier: moproshop.com` ×28 — an external
  prober (`TLM-Audit-Scanner/1.0`, remote 104.23.x) hitting `/.well-known/acme-challenge/*`
  unsolicited; Caddy logs a warn when no live order matches. Not our issuance failing.

## 3. Preconditions + proof the path works (§2.3)

- **Issuance through this exact setup has succeeded repeatedly:**
  - `api-staging` + `staging.moproshop.com`: `"certificate obtained successfully"` (HTTP-01, LE prod, 2026-05-26).
  - `moproshop.com` + `www`: certs now expire **Aug 24** — successfully RE-issued ≈ May 26.
- **CAA:** no CAA records on `moproshop.com` (any CA permitted) — not a factor.
- **Host resolver: the weakness.** `/etc/resolv.conf` = **single `nameserver 8.8.8.8`**, no
  `/etc/docker/daemon.json` → every container's external DNS rides one upstream with zero
  redundancy. One SERVFAIL-y window (as on Jun 1–2) takes out ACME reachability for its duration.
- **Live intermittency check (2026-06-07):** 20/20 lookups OK via container default DNS AND via
  explicit 1.1.1.1 — the issue is episodic, currently quiescent.

## 4. Root cause (named)

**Intermittent SERVFAIL from the host's single upstream resolver (8.8.8.8) behind Docker's
embedded DNS — no resolver redundancy.** It degraded ARI refreshes (advisory) and would only
threaten an actual renewal if a multi-day resolver outage (Jun 1–2-shaped) landed inside the
~30-day renewal/retry window. Caddy's retry loop has absorbed every episode so far (no failed
issuance on record; two domains already renewed through it).

## 5. Fix (Outcome A — single config change) + risk framing

Add per-container DNS redundancy to the **caddy** service in `deploy/docker-compose.prod.yml`:

```yaml
    dns: [1.1.1.1, 8.8.8.8, 9.9.9.9]
```

Docker's embedded DNS then fails over between three independent anycast resolvers; a single
upstream SERVFAIL no longer breaks ACME traffic. No Caddyfile change (the error is below Caddy);
no challenge/issuer/email change; existing certs and the `/data` volume untouched.

**Delivery shift vs. the prompt's hotfix note:** this is a *compose-level* change → applying it
on-host is `docker compose -f … up -d caddy` (container **recreate**, ≈2–5 s listener blip;
cert state persists in the named volume) — **not** `caddy reload` (which only re-reads the
Caddyfile). Run off-peak. `caddy validate` still gates any config apply per protocol.

Optional host-hardening for Salih (out of repo scope): add a second `nameserver` to the VDS
`/etc/resolv.conf` — benefits every container, not just Caddy.

## 6. Testing protocol mapping (§3, honest constraints)

A true staging *issuance* cannot be exercised without touching prod serving: HTTP-01/TLS-ALPN
require ports 80/443, which the live Caddy owns, and any staging-CA site block means reloading
the production instance — barred by anti-goals 2/4/7. Equivalent evidence, since the root cause
is DNS/reachability (not challenge semantics):

1. `caddy validate` the (unchanged) Caddyfile in a throwaway local container — config gate.
2. **LE staging endpoint exercised** from a one-off container on the prod host running with the
   proposed `dns:` settings: N× resolve + fetch `https://acme-staging-v02.api.letsencrypt.org/directory`
   — must be 0-failure. (Directory GETs are not issuance; no rate-limit exposure.)
3. Prod-CA *reachability* (resolve + directory GET) the same way — no order placed.
4. Renewal-path confirmation = runbook: post-deploy, `grep "got renewal info"` stays clean of
   `server misbehaving`; the weekly cert-backstop (Sundays 2026-07-19 → 08-17) confirms NotAfter
   rolls forward. Earliest expiry **2026-08-18** (api/seller/admin/fin); moproshop.com/www/staging
   are already at Aug 24.
