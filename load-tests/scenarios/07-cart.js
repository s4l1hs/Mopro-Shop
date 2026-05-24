/**
 * S7 — Cart operations (Redis Lua atomicity under contention).
 * Tests add item (→ 404 unknown variant), get cart (→ 200 empty),
 * and reserve (→ 422 empty cart). Validates the full cart middleware
 * and Redis path without requiring seeded products.
 */
import http from 'k6/http';
import { sleep } from 'k6';
import { BASE_URL, readParams, writeParams } from '../k6.config.js';
import { assertAnyOf, assertResponse, randomSleep } from '../lib/checks.js';
import { getAuth } from '../lib/auth.js';
import { newIdempotencyKey } from '../lib/idempotency.js';

export function cartTest() {
  const { token } = getAuth();

  // ── ADD ITEM (non-existent variant — tests middleware chain) ─────────────
  const addRes = http.post(
    `${BASE_URL}/cart/items`,
    JSON.stringify({ variant_id: 999999, qty: 1 }),
    {
      ...writeParams(token, newIdempotencyKey()),
      // 404/422 are design-expected; exclude from http_req_failed.
      responseCallback: http.expectedStatuses(404, 422),
    },
  );
  assertAnyOf(addRes, [404, 422], 'cart-add-item');

  sleep(0.1);

  // ── GET CART (always 200, may be empty) ──────────────────────────────────
  const getRes = http.get(`${BASE_URL}/cart`, readParams(token));
  assertResponse(getRes, 200, 'cart-get');

  sleep(0.1);

  // ── RESERVE (empty cart → 422 Unprocessable) ─────────────────────────────
  const reserveRes = http.post(
    `${BASE_URL}/cart/reserve`,
    '{}',
    {
      ...writeParams(token, newIdempotencyKey()),
      responseCallback: http.expectedStatuses(422, 409),
    },
  );
  assertAnyOf(reserveRes, [422, 409], 'cart-reserve');

  sleep(randomSleep());
}
