# Load Test Reports

This directory holds generated reports from k6 test runs.

## File Naming

| Pattern                         | Description                        |
|---------------------------------|------------------------------------|
| `<profile>-<YYYY-MM-DDTHH-MM-SS>.md`  | Markdown summary (human-readable) |
| `<profile>-<YYYY-MM-DDTHH-MM-SS>.json`| Raw k6 summary export             |

## Report Contents

Each markdown report contains:

1. **Summary** — total requests, throughput (req/s), error rate, check pass rate
2. **SLO Pass/Fail matrix** — ✅/❌ for each of the 8 latency/error SLOs
3. **Latency distribution** — p50/p95/p99 for read and write tiers
4. **Top 5 slowest endpoints** — by p95, helps find bottlenecks
5. **VDS resource peaks** — manual paste from `sudo docker stats`
6. **Discoveries / Bottlenecks** — filled in manually after review

## Gitignore Policy

- `*.json` and `*.md` outputs are gitignored (may contain timing data or tokens)
- Only `.gitkeep` and this `README.md` are committed
- To share a report, copy it out of this directory and attach to the PR

## Baseline Expectations (pre-launch, no real traffic)

With the single VDS (6 vCPU, 24 GB RAM) at idle:

- `/v1/categories` p95 should be < 30 ms (simple DB query)
- `/v1/search?q=*` p95 should be < 150 ms (Meilisearch hit)
- `/v1/addresses` CRUD p95 should be < 200 ms (PII encryption + DB write)
- Error rate should be 0% during baseline (no real users competing)

Any deviation from these expectations indicates a config or performance issue
that should be investigated before launch.
