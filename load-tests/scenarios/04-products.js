/**
 * S4 — Products list (read, may return empty data pre-catalog-seed).
 * Tests /v1/products?category_id=1 — validates the DB path and response
 * shape even when no products exist yet.
 * No auth required. Expected: 200.
 */
import http from 'k6/http';
import { sleep } from 'k6';
import { BASE_URL, readParams } from '../k6.config.js';
import { assertResponse, randomSleep } from '../lib/checks.js';

// Rotate through several category IDs to avoid single-key DB hot spots.
const CATEGORY_IDS = [1, 2, 3, 4, 5, 6, 7, 8];

export function productsTest() {
  const catId = CATEGORY_IDS[__VU % CATEGORY_IDS.length];
  const res = http.get(
    `${BASE_URL}/v1/products?category_id=${catId}&limit=20`,
    readParams(null),
  );

  // 200 with any body (empty array is fine — catalog not seeded yet).
  assertResponse(res, 200, 'products');

  sleep(randomSleep());
}
