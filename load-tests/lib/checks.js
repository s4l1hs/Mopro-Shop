/**
 * Reusable HTTP check helpers.
 * Wraps k6's check() so each scenario can express expectations clearly.
 */
import { check } from 'k6';
import { Rate } from 'k6/metrics';

export const errorRate = new Rate('custom_error_rate');

/**
 * Assert response status and optionally validate JSON shape.
 * Returns true if all checks pass.
 *
 * @param {Response}  res        - k6 HTTP response
 * @param {number}    wantStatus - expected HTTP status code
 * @param {string}    label      - human-readable name for the check
 * @param {Function}  [bodyFn]   - optional function(parsed JSON) → bool
 */
export function assertResponse(res, wantStatus, label, bodyFn) {
  const ok = check(res, {
    [`${label}: status=${wantStatus}`]: (r) => r.status === wantStatus,
    ...(bodyFn ? { [`${label}: body valid`]: (r) => {
      try { return bodyFn(r.json()); } catch (_) { return false; }
    }} : {}),
  });
  errorRate.add(!ok);
  return ok;
}

/**
 * Assert one of several acceptable status codes (for paths where we expect
 * a 4xx by design — empty cart, unknown variant, etc.).
 */
export function assertAnyOf(res, statuses, label) {
  const ok = check(res, {
    [`${label}: status in [${statuses.join(',')}]`]: (r) => statuses.includes(r.status),
  });
  errorRate.add(!ok);
  return ok;
}

/** Random sleep between minMs and maxMs milliseconds (realistic user pacing). */
export function randomSleep(minMs = 100, maxMs = 300) {
  const ms = minMs + Math.random() * (maxMs - minMs);
  // k6 sleep takes seconds
  return ms / 1000;
}
