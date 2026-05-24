/**
 * Shared handleSummary implementation.
 * Generates a Markdown report and writes it to reports/<profile>-<date>.md.
 * Imported by every profile script.
 */

function fmtMs(v) {
  if (v === undefined || v === null) return 'n/a';
  return `${v.toFixed(1)} ms`;
}

function fmtRate(v) {
  if (v === undefined || v === null) return 'n/a';
  return `${(v * 100).toFixed(2)}%`;
}

function sloStatus(metric, name, threshold) {
  if (!metric) return '⬜ n/a';
  // threshold looks like 'p(95)<300' or 'rate<0.005'
  const rateMatch = threshold.match(/^rate<([\d.]+)$/);
  const pctMatch  = threshold.match(/^rate>([\d.]+)$/);
  const durMatch  = threshold.match(/^p\((\d+)\)<([\d.]+)$/);

  let actual, limit, pass;
  if (rateMatch) {
    limit  = parseFloat(rateMatch[1]);
    actual = metric.values && metric.values.rate;
    pass   = actual !== undefined && actual < limit;
    return `${pass ? '✅' : '❌'} ${fmtRate(actual)} < ${fmtRate(limit)}`;
  }
  if (pctMatch) {
    limit  = parseFloat(pctMatch[1]);
    actual = metric.values && metric.values.rate;
    pass   = actual !== undefined && actual > limit;
    return `${pass ? '✅' : '❌'} ${fmtRate(actual)} > ${fmtRate(limit)}`;
  }
  if (durMatch) {
    const pct = durMatch[1];
    limit     = parseFloat(durMatch[2]);
    actual    = metric.values && (metric.values[`p(${pct})`]
                  || (pct === '50' ? metric.values['med'] : undefined));
    pass      = actual !== undefined && actual < limit;
    return `${pass ? '✅' : '❌'} p${pct}=${fmtMs(actual)} < ${limit} ms`;
  }
  return '⬜ unknown';
}

function topEndpoints(metrics, n = 5) {
  // Find all http_req_duration sub-metrics and rank by p95.
  const rows = [];
  for (const [key, val] of Object.entries(metrics)) {
    if (!key.startsWith('http_req_duration{') || !val.values) continue;
    const tag = key.match(/\{([^}]+)\}/)?.[1] || key;
    rows.push({ tag, p95: val.values['p(95)'] || 0, p99: val.values['p(99)'] || 0 });
  }
  rows.sort((a, b) => b.p95 - a.p95);
  return rows.slice(0, n);
}

export function handleSummary(data) {
  const profile  = __ENV.K6_PROFILE || 'unknown';
  const date     = new Date().toISOString().split('T')[0];
  const ts       = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const filename = `reports/${profile}-${ts}.md`;

  const m = data.metrics;

  // ── Latency table ──────────────────────────────────────────────────────────
  const latRead  = m['http_req_duration{type:read}'];
  const latWrite = m['http_req_duration{type:write}'];
  const httpFail = m['http_req_failed'];
  const checks   = m['checks'];
  const rps      = m['http_reqs'];

  // p(50) is exported when summaryTrendStats includes it; fall back to med.
  const p50r = latRead  && (latRead.values['p(50)']  || latRead.values['med']);
  const p50w = latWrite && (latWrite.values['p(50)'] || latWrite.values['med']);

  const latencyRows = [
    ['Read  p50',  fmtMs(p50r)],
    ['Read  p95',  fmtMs(latRead  && latRead.values['p(95)'])],
    ['Read  p99',  fmtMs(latRead  && latRead.values['p(99)'])],
    ['Write p50',  fmtMs(p50w)],
    ['Write p95',  fmtMs(latWrite && latWrite.values['p(95)'])],
    ['Write p99',  fmtMs(latWrite && latWrite.values['p(99)'])],
  ];

  const sloRows = [
    ['Read  p50 < 100 ms',   sloStatus(latRead,  'read',  'p(50)<100')],
    ['Read  p95 < 300 ms',   sloStatus(latRead,  'read',  'p(95)<300')],
    ['Read  p99 < 1000 ms',  sloStatus(latRead,  'read',  'p(99)<1000')],
    ['Write p50 < 200 ms',   sloStatus(latWrite, 'write', 'p(50)<200')],
    ['Write p95 < 500 ms',   sloStatus(latWrite, 'write', 'p(95)<500')],
    ['Write p99 < 2000 ms',  sloStatus(latWrite, 'write', 'p(99)<2000')],
    ['Error rate < 0.5%',    sloStatus(httpFail, 'fail',  'rate<0.005')],
    ['Check pass rate > 99.5%', sloStatus(checks, 'chk', 'rate>0.995')],
  ];

  const topSlowEndpoints = topEndpoints(m);

  const md = `# Mopro Load Test Report — ${profile} — ${date}

## Summary

| Metric         | Value |
|----------------|-------|
| Profile        | ${profile} |
| Run date       | ${date} |
| Total requests | ${rps && rps.values ? rps.values.count : 'n/a'} |
| Throughput     | ${rps && rps.values ? `${rps.values.rate.toFixed(1)} req/s` : 'n/a'} |
| Error rate     | ${fmtRate(httpFail && httpFail.values.rate)} |
| Check pass     | ${fmtRate(checks && checks.values.rate)} |

## SLO Pass / Fail

| SLO                     | Result |
|-------------------------|--------|
${sloRows.map(([slo, res]) => `| ${slo.padEnd(23)} | ${res} |`).join('\n')}

## Latency Distribution

| Metric     | Value |
|------------|-------|
${latencyRows.map(([k, v]) => `| ${k.padEnd(10)} | ${v} |`).join('\n')}

## Top 5 Slowest Endpoints (by p95)

| Endpoint tag           | p95       | p99       |
|------------------------|-----------|-----------|
${topSlowEndpoints.length
  ? topSlowEndpoints.map(r => `| ${r.tag.padEnd(22)} | ${fmtMs(r.p95)} | ${fmtMs(r.p99)} |`).join('\n')
  : '| (no tagged data)       | n/a       | n/a       |'}

## VDS Resource Peaks

> Run \`ssh -p 4625 mopro@195.85.207.92 'sudo docker stats --no-stream'\`
> during the test and paste the output here.

\`\`\`
(paste docker stats output)
\`\`\`

## Discoveries / Bottlenecks

_Fill in after reviewing the numbers above._

---
*Generated by k6 / Mopro load test harness. Profile: ${profile}*
`;

  // Write to stdout (human-readable console summary) AND to file.
  return {
    stdout:   `\n=== Summary export → ${filename} ===\n`,
    [filename]: md,
  };
}
