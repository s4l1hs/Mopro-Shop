/**
 * S8 — Checkout initiate (saga path — expect 422 or 400 for missing/expired
 * reservation). Tests the full middleware + validation chain including disk
 * pressure check, JWT auth, and saga entry point.
 */
import http from 'k6/http';
import { sleep } from 'k6';
import { BASE_URL, writeParams } from '../k6.config.js';
import { assertAnyOf, randomSleep } from '../lib/checks.js';
import { getAuth } from '../lib/auth.js';
import { newIdempotencyKey } from '../lib/idempotency.js';

export function checkoutTest() {
  const { token } = getAuth();

  // POST with a fake reservation ID — tests the full auth + validation path.
  // 400/422 = expected (reservation not found or validation error).
  const res = http.post(
    `${BASE_URL}/checkout/initiate`,
    JSON.stringify({
      reservation_id: 'load-test-fake-reservation-000',
      market:         'TR',
      currency:       'TRY',
    }),
    {
      ...writeParams(token, newIdempotencyKey()),
      // 400/404/422 are design-expected; exclude from http_req_failed.
      responseCallback: http.expectedStatuses(400, 404, 422),
    },
  );

  // Accept 400, 404, 422 — any clean rejection means the path worked correctly.
  // 500 would be a real bug.
  assertAnyOf(res, [400, 404, 422], 'checkout-initiate');

  sleep(randomSleep());
}
