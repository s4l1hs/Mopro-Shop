/**
 * S6 — Address CRUD (write path, PII encryption load).
 * Full create → list → get → update → delete cycle per iteration.
 * Requires JWT auth. Each iteration creates a fresh address to avoid
 * accumulating stale data and to exercise the full write path.
 */
import http from 'k6/http';
import { sleep } from 'k6';
import { BASE_URL, readParams, writeParams } from '../k6.config.js';
import { assertResponse, assertAnyOf, randomSleep } from '../lib/checks.js';
import { getAuth } from '../lib/auth.js';
import { newIdempotencyKey } from '../lib/idempotency.js';

function testAddress(phone) {
  return {
    label:        'Load Test Address',
    name:         'Yük Testi Kullanıcısı',
    phone:        phone,
    full_address: 'Bağdat Caddesi No:1',
    city:         'İstanbul',
    district:     'Kadıköy',
    postal_code:  '34710',
  };
}

export function addressesTest() {
  const { phone, token } = getAuth();

  // ── CREATE ──────────────────────────────────────────────────────────────────
  const createRes = http.post(
    `${BASE_URL}/addresses`,
    JSON.stringify(testAddress(phone)),
    writeParams(token, newIdempotencyKey()),
  );
  const created = assertResponse(createRes, 201, 'address-create');
  if (!created) {
    sleep(randomSleep());
    return;
  }

  const body = createRes.json();
  // Support both {id:...} and {address:{id:...}} response shapes.
  const addrId = body.id || (body.address && body.address.id);
  if (!addrId) {
    sleep(randomSleep());
    return;
  }

  sleep(0.1);

  // ── LIST ────────────────────────────────────────────────────────────────────
  const listRes = http.get(`${BASE_URL}/addresses`, readParams(token));
  assertResponse(listRes, 200, 'address-list');

  sleep(0.1);

  // ── GET ONE ─────────────────────────────────────────────────────────────────
  const getRes = http.get(`${BASE_URL}/addresses/${addrId}`, readParams(token));
  assertResponse(getRes, 200, 'address-get');

  sleep(0.1);

  // ── UPDATE ──────────────────────────────────────────────────────────────────
  const updated = { ...testAddress(phone), label: 'Load Test Address Updated' };
  const putRes = http.put(
    `${BASE_URL}/addresses/${addrId}`,
    JSON.stringify(updated),
    writeParams(token, newIdempotencyKey()),
  );
  assertAnyOf(putRes, [200, 204], 'address-update');

  sleep(0.1);

  // ── DELETE ──────────────────────────────────────────────────────────────────
  const delRes = http.del(
    `${BASE_URL}/addresses/${addrId}`,
    null,
    writeParams(token, null),
  );
  assertAnyOf(delRes, [200, 204], 'address-delete');

  sleep(randomSleep());
}
