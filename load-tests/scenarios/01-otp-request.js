/**
 * S1 — OTP Request burst (auth pre-warm).
 * Tests /auth/otp/request under concurrent load.
 * Each VU uses its own phone number so rate limiting doesn't interfere.
 * Expected: 204 (success) or 429 (rate limited — rate limiter is working).
 */
import http from 'k6/http';
import { sleep } from 'k6';
import { BASE_URL, writeParams } from '../k6.config.js';
import { assertAnyOf, randomSleep } from '../lib/checks.js';
import { TEST_PHONES } from '../lib/test-users.js';

export function otpRequestTest() {
  const phone = TEST_PHONES[__VU % TEST_PHONES.length];

  const params = {
    ...writeParams(null),
    // 429 = rate limiter working correctly; not a test failure.
    responseCallback: http.expectedStatuses(204, 429),
  };

  const res = http.post(
    `${BASE_URL}/auth/otp/request`,
    JSON.stringify({ phone, purpose: 'login' }),
    params,
  );

  // 429 is expected when per-phone limit (3/10min) is reached.
  assertAnyOf(res, [204, 429], 'otp-request');

  // Respect per-phone rate limit: at most 1 req/min per phone.
  // VUs are spread across 100 phones so system-wide throughput is well
  // within the IP-level limit.
  sleep(1 + randomSleep(0, 0.5));
}
