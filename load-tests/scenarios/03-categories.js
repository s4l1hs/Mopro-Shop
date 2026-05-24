/**
 * S3 — Categories list (cached, read-heavy).
 * Tests /categories — the most cache-friendly endpoint.
 * No auth required. Expected: 200 with JSON array.
 */
import http from 'k6/http';
import { sleep } from 'k6';
import { BASE_URL, readParams } from '../k6.config.js';
import { assertResponse, randomSleep } from '../lib/checks.js';

export function categoriesTest() {
  const res = http.get(`${BASE_URL}/categories`, readParams(null));

  assertResponse(res, 200, 'categories', (b) =>
    Array.isArray(b) || (b && (Array.isArray(b.categories) || Array.isArray(b.data)))
  );

  sleep(randomSleep());
}
