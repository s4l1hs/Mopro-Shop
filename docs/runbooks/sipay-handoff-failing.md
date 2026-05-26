# Runbook: SipayHandoffFailing

## Severity
warning

## What this means
More than 10% of Sipay API calls are returning non-2xx responses for at least 15 minutes (`sipay_request_total{status!~"2.*"}` ratio > 0.10). Sipay is the primary PSP for TR launch. Elevated failure rates mean checkout payments are being rejected, declined, or timing out at the PSP layer.

## Common causes
- Sipay API is experiencing a partial or full outage (check their status page)
- API credentials expired or rotated on the Sipay dashboard without updating `.env`
- Sipay IP allowlist does not include the VDS IP (VDS IP changed after a provider migration)
- 3DS redirect URL misconfiguration after a deploy (return URL changed)
- Rate limiting: Sipay is throttling due to too many requests per second (unusual for current traffic level)
- Sipay endpoint URL changed (v2 API migration)
- TLS certificate issue on the Sipay side

## Investigation steps
1. **Identify the failing endpoint**: Grafana → Financial Health → "PSP (Sipay)" row → "Request Status Piechart" and "Latency by Endpoint" — which endpoint is failing
2. **Check Sipay status page**: `https://status.sipay.com.tr` (or check their Slack/email integration if subscribed)
3. **Inspect recent Sipay error responses**: `docker compose logs core-svc | grep -i sipay | grep -i error | tail -50`
4. **Check credentials**: Verify `SIPAY_API_KEY` and `SIPAY_MERCHANT_KEY` in `/opt/mopro/.env` match the active keys in the Sipay merchant dashboard
5. **Check VDS IP allowlist**: From the VDS: `curl -s https://api.sipay.com.tr/v2/health` (or equivalent) — a 403 may indicate IP block
6. **Check 3DS return URL**: In the Sipay dashboard, verify the `return_url` / `cancel_url` match the current Caddy routing
7. **Check request volume**: `sipay_request_total` rate — if > expected, might be a retry storm from a bug

## Mitigation
- **If Sipay is down**: no immediate action possible on our side. Monitor their status page. Consider surfacing a temporary user-facing message: "Ödeme servisi geçici olarak kullanılamıyor."
- **If credentials expired**: update `SIPAY_API_KEY` in `.env`; restart core-svc: `docker compose -f deploy/docker-compose.prod.yml restart core-svc`
- **If IP not allowlisted**: add the VDS IP to the Sipay merchant dashboard allowlist
- **If 3DS URL mismatch**: update the return URL in the Sipay dashboard (no redeploy needed if the URL is configured there, not in code)
- **Craftgate failover** (if configured as backup provider): set `PSP_PROVIDER=craftgate` in `.env`; restart core-svc — the PSP adapter pattern switches providers with no code change

## Escalation
- Slack: #mopro-eng (warning)
- If failure rate exceeds 50% for > 30 minutes: escalate to #mopro-panic and notify Finance team
- If revenue impact is suspected: notify business lead for customer communication

## Post-incident
- Record Sipay incident reference number and duration in incident doc
- If credentials were the cause: add a reminder to the ops calendar for credential expiry
- Verify Craftgate backup provider is configured and tested in staging
- Add `sipay_request_total` error budget to the SLO overview dashboard
