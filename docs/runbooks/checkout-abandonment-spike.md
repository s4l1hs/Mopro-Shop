# Runbook: CheckoutAbandonmentSpike

## Severity
warning

## What this means
The ratio of `cart→abandoned` order status transitions to `cart→checkout` transitions has exceeded 40% for at least 30 minutes. In normal operation, most users who start checkout complete it. A spike here signals friction in the checkout funnel: payment failures, slow load times, UX bugs, or PSP-side issues.

## Common causes
- Sipay or another PSP is returning errors (failed payment attempts → user abandons)
- High API latency on the checkout or payment capture route making users give up
- A mobile app or web UI bug introduced in a recent deploy (e.g., broken 3DS redirect)
- OTP verification step failing (identity/OTP service error)
- A promotional campaign driving high traffic from unconverted users (no real regression)
- Session timeout during checkout forcing re-login
- Geographic latency spike (CloudFlare routing issue for TR users)

## Investigation steps
1. **Correlate with Sipay errors**: Check Grafana → Financial Health → "PSP (Sipay)" row first — if `SipayHandoffFailing` is also firing, PSP is the primary cause; follow `docs/runbooks/sipay-handoff-failing.md`
2. **Check API latency on checkout routes**: Grafana → SLO Overview → "Top 10 Routes" — look for `POST /checkout` or `POST /payment/capture` latency spikes
3. **Check 5xx errors on payment route**: Filter `mopro_http_requests_total{route=~"/payment.*", status=~"5.."}` in Grafana Explore
4. **Check for a recent deploy**: `git log --oneline -5` — correlate abandonment spike onset with deploy time
5. **Check OTP endpoint**: `mopro_http_requests_total{route="/auth/otp.*", status!~"2.."}` — OTP failures cause checkout drop
6. **Check mobile crash reports** (if mobile observability is set up) — a 3DS webview crash shows here
7. **Check CloudFlare analytics**: Log into the CloudFlare dashboard → Analytics → check TR-region latency and error rates

## Mitigation
- **If PSP is causing it**: follow `docs/runbooks/sipay-handoff-failing.md`
- **If latency is causing it**: follow `docs/runbooks/api-latency-p95-high.md`
- **If a deploy caused a UI/flow regression**: roll back to the previous build per `deploy/RUNBOOK.md` § "Rollback manually" (pinned `:<full-sha>` GHCR tag)
- **If OTP is broken**: check identity service logs; if a config issue, fix and restart core-svc
- **If traffic spike from campaign** (no errors, just high volume): monitor; no action if error rates are normal

## Escalation
- Slack: #mopro-eng (warning; inform product team if abandonment > 60% for > 1h)
- If revenue impact is confirmed: escalate to #mopro-panic and notify business/Finance leads

## Post-incident
- Record abandonment rate, duration, and root cause in incident doc
- If a deploy caused a regression: add a checkout E2E smoke test to the pre-deploy checklist
- Review funnel data in the analytics system to quantify lost revenue
