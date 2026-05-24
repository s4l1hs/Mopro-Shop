/**
 * S5 — Search (Postgres tsvector / Meilisearch hit).
 * Tests /search?q=<term> with common Turkish fashion queries.
 * No auth required. Expected: 200.
 */
import http from 'k6/http';
import { sleep } from 'k6';
import { BASE_URL, readParams } from '../k6.config.js';
import { assertResponse, randomSleep } from '../lib/checks.js';

// Representative Turkish search terms — fashion marketplace vocab.
const QUERIES = [
  'elbise', 'mont', 'ayakkabı', 'çanta', 'kazak',
  'pantolon', 'etek', 'gömlek', 'ceket', 'bot',
];

export function searchTest() {
  const q = QUERIES[(__VU + __ITER) % QUERIES.length];
  const res = http.get(
    `${BASE_URL}/search?q=${encodeURIComponent(q)}&limit=20`,
    readParams(null),
  );

  assertResponse(res, 200, 'search');

  sleep(randomSleep());
}
