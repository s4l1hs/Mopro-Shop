# Mopro Load Testing Harness

k6-based load testing for all critical buyer paths. Correlates with Phase 5.4
Prometheus metrics (`mopro_http_requests_total`, `mopro_http_request_duration_seconds`).

## Prerequisites

```bash
# Install k6 (macOS)
brew install k6

# Verify
k6 version   # k6 v2.0.0+

# OR run via Docker (no install needed):
# docker run --rm -v "$PWD:/load-tests" grafana/k6 run /load-tests/profiles/smoke.js
```

SSH key access to the VDS is required for OTP extraction from docker logs.
Verify with: `ssh -p 4625 mopro@195.85.207.92 echo ok`

## Quick Start

```bash
cd load-tests/

# 1. Provision 100 test users (one-time, idempotent)
./setup.sh

# 2. Run a smoke test (5 VUs, 30 s — confirms everything works)
./run.sh smoke

# 3. Run the baseline capacity test (50 VUs, 5 min)
./run.sh baseline
```

## Test Profiles

| Profile  | VUs | Duration | Purpose                        |
|----------|-----|----------|--------------------------------|
| smoke    | 5   | 30 s     | Does it work at all?           |
| baseline | 50  | 5 min    | Typical launch-day traffic     |
| stress   | 200 | 5+5 min  | Find the saturation knee ⚠️    |
| spike    | 500 | 1 min    | Burst / flash-sale simulation ⚠️|
| soak     | 50  | 30 min   | Memory leaks, pool exhaustion  |

⚠️ = warn Salih before running against production.

## Scenarios

| # | Endpoint                        | Method | Expected |
|---|----------------------------------|--------|----------|
| 1 | `/v1/auth/otp/request`          | POST   | 204      |
| 2 | `/v1/auth/otp/verify`           | POST   | 200      |
| 3 | `/v1/categories`                | GET    | 200      |
| 4 | `/v1/products?category_id=X`    | GET    | 200      |
| 5 | `/v1/search?q=elbise`           | GET    | 200      |
| 6 | `/v1/addresses` CRUD            | CRUD   | 201/200/204 |
| 7 | `/v1/cart` operations           | CRUD   | 200/422  |
| 8 | `/v1/checkout/initiate`         | POST   | 400/422  |

## SLO Targets (D6)

| Metric        | Target   |
|---------------|----------|
| Read p50      | < 100 ms |
| Read p95      | < 300 ms |
| Read p99      | < 1000 ms|
| Write p50     | < 200 ms |
| Write p95     | < 500 ms |
| Write p99     | < 2000 ms|
| Error rate    | < 0.5%   |
| Check pass    | > 99.5%  |

## File Structure

```
load-tests/
├── k6.config.js          # BASE_URL, SLO thresholds, shared param helpers
├── setup.sh              # Provision 100 test users + addresses (one-time)
├── run.sh                # Run a profile: ./run.sh baseline
├── lib/
│   ├── auth.js           # Token cache loader (SharedArray from .tokens.json)
│   ├── checks.js         # assertResponse() / assertAnyOf() wrappers
│   ├── idempotency.js    # UUID v4 generator for Idempotency-Key headers
│   ├── summary.js        # handleSummary() — Markdown report generator
│   └── test-users.js     # 100 test phone numbers
├── scenarios/
│   ├── 01-otp-request.js
│   ├── 02-otp-verify.js
│   ├── 03-categories.js
│   ├── 04-products.js
│   ├── 05-search.js
│   ├── 06-addresses.js
│   ├── 07-cart.js
│   └── 08-checkout.js
├── profiles/
│   ├── smoke.js
│   ├── baseline.js
│   ├── stress.js
│   ├── spike.js
│   └── soak.js
└── reports/
    ├── .gitkeep
    └── README.md         # Report format documentation
```

## Correlating with Prometheus Metrics

While the test runs, scrape the services' `/metrics` endpoints to see
`mopro_http_requests_total` increasing:

```bash
# From the VDS (or locally if port-forwarded):
curl -sf http://core-svc:9100/metrics | grep mopro_http_requests_total
```

Or open Grafana Cloud and watch the dashboards in real time.

## Gitignore

The following are gitignored:
- `.tokens.json` — contains JWT tokens (secrets)
- `.refresh.json` — refresh tokens
- `.otps.json` — short-lived OTP codes
- `reports/*.json` — raw k6 output
- `reports/*.md` — generated markdown reports (except this README)
