/**
 * scripts/loadtest/k6-smoke.js — Mopro L9 synthetic load test
 *
 * Simulates realistic anonymous browsing traffic with occasional authenticated
 * checkout attempts (at low rate, since each checkout calls Sipay sandbox).
 *
 * Usage:
 *   k6 run --env BASE=https://api-staging.moproshop.com scripts/loadtest/k6-smoke.js
 *   make loadtest
 *
 * SLO thresholds (L9 baseline — tune after observing real signal):
 *   p95 browse latency < 500ms
 *   p99 browse latency < 2000ms
 *   error rate < 1%
 *
 * Prerequisites:
 *   - k6 installed: brew install k6  or  https://k6.io/docs/get-started/installation/
 *   - Staging stack running with seed data (make seed-staging)
 *   - DEV_OTP_ACCEPT_ANY=true on staging (for auth scenario)
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Rate } from 'k6/metrics';

// ── Custom metrics ────────────────────────────────────────────────────────────
const checkoutAttempts = new Counter('checkout_attempts_total');
const checkoutErrors   = new Counter('checkout_errors_total');
const authErrors       = new Rate('auth_error_rate');

// ── Test configuration ────────────────────────────────────────────────────────
export const options = {
  scenarios: {
    // Primary: anonymous browse traffic — majority of real-world load
    browsing: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m',  target: 50  },  // ramp up to 50 VUs
        { duration: '5m',  target: 50  },  // sustain
        { duration: '1m',  target: 100 },  // burst to 100 VUs
        { duration: '2m',  target: 100 },  // sustain burst
        { duration: '1m',  target: 0   },  // ramp down
      ],
      gracefulRampDown: '30s',
      exec: 'browseScenario',
    },
    // Secondary: low-rate authenticated checkout (3 VUs, staggered)
    // Validates the full auth→cart→reserve→checkout path under concurrent load.
    checkout: {
      executor: 'constant-vus',
      vus: 3,
      duration: '8m',
      startTime: '30s',  // start after browsing has warmed up
      exec: 'checkoutScenario',
    },
  },
  thresholds: {
    // Core SLO: p95 < 500ms for browse traffic (CLAUDE.md L9 requirement)
    'http_req_duration{type:browse}': ['p(95)<500', 'p(99)<2000'],
    // Auth-required reads (wallet/cashback from fin-svc) are allowed to be slower
    'http_req_duration{type:fin}':    ['p(95)<800'],
    // Error rate across all requests
    'http_req_failed':                ['rate<0.01'],
    // Auth should rarely fail on staging with bypass enabled
    'auth_error_rate':                ['rate<0.05'],
  },
};

const BASE = __ENV.BASE || 'https://api-staging.moproshop.com';

// ── Browse scenario (anonymous traffic) ──────────────────────────────────────
export function browseScenario() {
  const r = Math.random();

  if (r < 0.35) {
    // Product list (most common: browsing catalog)
    group('product_list', () => {
      const res = http.get(
        `${BASE}/products?category_id=127&sort=bestseller&limit=12`,
        { tags: { type: 'browse', route: '/products' } }
      );
      check(res, {
        'products list 200': (r) => r.status === 200,
        'products has items': (r) => {
          try {
            const body = JSON.parse(r.body);
            const items = body.data || body.items || [];
            return items.length > 0;
          } catch { return false; }
        },
      });
    });

  } else if (r < 0.55) {
    // Category list
    group('category_list', () => {
      const res = http.get(
        `${BASE}/categories`,
        { tags: { type: 'browse', route: '/categories' } }
      );
      check(res, { 'categories 200': (r) => r.status === 200 });
    });

  } else if (r < 0.75) {
    // Search
    const queries = ['kulaklik', 'telefon', 'laptop', 'kiyafet', 'ayakkabi'];
    const q = queries[Math.floor(Math.random() * queries.length)];
    group('search', () => {
      const res = http.get(
        `${BASE}/search?q=${q}`,
        { tags: { type: 'browse', route: '/search' } }
      );
      check(res, { 'search 200': (r) => r.status === 200 });
    });

  } else if (r < 0.88) {
    // Product detail (PDP) — get a product first then fetch detail
    group('pdp', () => {
      const listRes = http.get(
        `${BASE}/products?category_id=127&limit=20`,
        { tags: { type: 'browse', route: '/products' } }
      );
      if (listRes.status === 200) {
        try {
          const body = JSON.parse(listRes.body);
          const items = body.data || body.items || [];
          if (items && items.length > 0) {
            const id = items[Math.floor(Math.random() * items.length)].id;
            const detailRes = http.get(
              `${BASE}/products/${id}`,
              { tags: { type: 'browse', route: '/products/{id}' } }
            );
            check(detailRes, { 'product detail 200': (r) => r.status === 200 });
          }
        } catch { /* ignore parse errors */ }
      }
    });

  } else {
    // Healthz heartbeat (small fraction — confirms proxy is alive)
    group('health', () => {
      const res = http.get(
        `${BASE}/healthz`,
        { tags: { type: 'browse', route: '/healthz' } }
      );
      check(res, { 'healthz 200': (r) => r.status === 200 });
    });
  }

  // Realistic think time: 0.5–2.5 seconds between requests
  sleep(Math.random() * 2 + 0.5);
}

// ── Checkout scenario (authenticated low-rate) ────────────────────────────────
export function checkoutScenario() {
  // Step 1: authenticate via OTP bypass
  const otpReqRes = http.post(
    `${BASE}/auth/otp/request`,
    JSON.stringify({ phone: '+905551234567' }),
    { headers: { 'Content-Type': 'application/json' }, tags: { type: 'auth' } }
  );

  check(otpReqRes, { 'otp/request 204': (r) => r.status === 204 });
  if (otpReqRes.status !== 204) {
    authErrors.add(1);
    sleep(5);
    return;
  }
  authErrors.add(0);

  const verifyRes = http.post(
    `${BASE}/auth/otp/verify`,
    JSON.stringify({ phone: '+905551234567', code: '123456' }),
    { headers: { 'Content-Type': 'application/json' }, tags: { type: 'auth' } }
  );

  let accessToken;
  try {
    accessToken = JSON.parse(verifyRes.body).access_token;
  } catch { /* ignore */ }

  if (!accessToken || verifyRes.status !== 200) {
    authErrors.add(1);
    sleep(5);
    return;
  }

  const authHeaders = {
    'Authorization': `Bearer ${accessToken}`,
    'Content-Type': 'application/json',
  };

  // Step 2: fetch product catalog to get a real variant ID
  const productsRes = http.get(
    `${BASE}/products?category_id=127&limit=5`,
    { tags: { type: 'browse' } }
  );
  let variantId;
  try {
    const body = JSON.parse(productsRes.body);
    const items = body.data || body.items || [];
    variantId = items[0].variants[0].id;
  } catch { /* ignore */ }

  if (!variantId) {
    sleep(3);
    return;
  }

  // Step 3: add to cart
  const cartAddRes = http.post(
    `${BASE}/cart/items`,
    JSON.stringify({ variant_id: variantId, qty: 1 }),
    { headers: authHeaders, tags: { type: 'browse', route: '/cart/items' } }
  );
  check(cartAddRes, { 'cart add 200': (r) => r.status === 200 });

  // Step 4: reserve cart
  const reserveRes = http.post(
    `${BASE}/cart/reserve`,
    '{}',
    { headers: authHeaders, tags: { type: 'browse', route: '/cart/reserve' } }
  );

  let reservationId;
  try {
    reservationId = JSON.parse(reserveRes.body).reservation_id;
  } catch { /* ignore */ }

  if (!reservationId) {
    // Clean up cart and return
    http.del(`${BASE}/cart/items/${variantId}`, null, { headers: authHeaders });
    sleep(3);
    return;
  }

  // Step 5: checkout initiate (Sipay sandbox)
  checkoutAttempts.add(1);
  const idempotencyKey = `k6-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const checkoutRes = http.post(
    `${BASE}/checkout/initiate`,
    JSON.stringify({
      reservation_id: reservationId,
      buyer_name: 'K6',
      buyer_surname: 'LoadTest',
      buyer_email: 'k6-loadtest@moproshop.com',
    }),
    {
      headers: { ...authHeaders, 'Idempotency-Key': idempotencyKey },
      tags: { type: 'checkout', route: '/checkout/initiate' },
    }
  );

  const checkoutOk = check(checkoutRes, {
    'checkout/initiate 200': (r) => r.status === 200,
  });
  if (!checkoutOk) {
    checkoutErrors.add(1);
    // Release reservation on failure to avoid leaving stale state
    http.post(
      `${BASE}/cart/release`,
      JSON.stringify({ reservation_id: reservationId }),
      { headers: authHeaders }
    );
  }

  // Step 6: fin-svc wallet balance (validates Caddy /wallet/* routing)
  const walletRes = http.get(
    `${BASE}/wallet/balance`,
    { headers: authHeaders, tags: { type: 'fin', route: '/wallet/balance' } }
  );
  check(walletRes, { 'wallet/balance 200': (r) => r.status === 200 });

  // Think time between checkout iterations — important to not hammer Sipay sandbox
  sleep(Math.random() * 10 + 5);
}

// ── Setup/teardown ─────────────────────────────────────────────────────────────
export function handleSummary(data) {
  // Print a concise summary at end of run for the L9 smoke report
  const dur = data.metrics['http_req_duration'];
  const failed = data.metrics['http_req_failed'];

  console.log('\n═══════════════════════════════════════════');
  console.log(' k6 Load Test Summary — Mopro L9 Smoke');
  console.log('═══════════════════════════════════════════');
  if (dur) {
    console.log(`  p50 : ${dur.values.med?.toFixed(0)}ms`);
    console.log(`  p95 : ${dur.values['p(95)']?.toFixed(0)}ms`);
    const p99 = dur.values['p(99)'] ?? dur.values['p99'];
    console.log(`  p99 : ${p99 !== undefined ? p99.toFixed(0) : 'n/a'}ms`);
    console.log(`  max : ${dur.values.max?.toFixed(0)}ms`);
  }
  if (failed) {
    console.log(`  err : ${(failed.values.rate * 100).toFixed(2)}%`);
  }
  const checkoutTotal = data.metrics['checkout_attempts_total']?.values?.count ?? 0;
  const checkoutErr   = data.metrics['checkout_errors_total']?.values?.count ?? 0;
  console.log(`  checkout attempts : ${checkoutTotal} (${checkoutErr} errors)`);
  console.log('═══════════════════════════════════════════\n');

  return {};
}
