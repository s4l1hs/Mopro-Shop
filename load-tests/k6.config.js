/**
 * Shared k6 configuration: base URL, SLO thresholds, common options.
 * Imported by every profile script.
 */

export const BASE_URL = (__ENV.BASE_URL || 'https://api.moproshop.com').replace(/\/$/, '');

/**
 * SLO thresholds (D6):
 *  read  → p50<100ms, p95<300ms, p99<1000ms
 *  write → p50<200ms, p95<500ms, p99<2000ms
 *  error rate < 0.5%  |  checks pass rate > 99.5%
 */
export const SUMMARY_TREND_STATS = ['med', 'p(50)', 'p(90)', 'p(95)', 'p(99)'];

export const SLO_THRESHOLDS = {
  'http_req_duration{type:read}':  ['p(50)<100',  'p(95)<300',  'p(99)<1000'],
  'http_req_duration{type:write}': ['p(50)<200',  'p(95)<500',  'p(99)<2000'],
  'http_req_failed':               ['rate<0.005'],
  'checks':                        ['rate>0.995'],
};

/** Common HTTP params shared across all scenarios. */
export function baseParams(token, extraHeaders = {}) {
  const h = {
    'Content-Type': 'application/json',
    'Accept':       'application/json',
    ...extraHeaders,
  };
  if (token) h['Authorization'] = `Bearer ${token}`;
  return { headers: h };
}

/** Return params tagged as a read request (feeds SLO threshold). */
export function readParams(token, extra = {}) {
  return { ...baseParams(token, extra), tags: { type: 'read' } };
}

/** Return params tagged as a write request. */
export function writeParams(token, idempotencyKey, extra = {}) {
  const extraH = idempotencyKey ? { 'Idempotency-Key': idempotencyKey, ...extra } : extra;
  return { ...baseParams(token, extraH), tags: { type: 'write' } };
}
