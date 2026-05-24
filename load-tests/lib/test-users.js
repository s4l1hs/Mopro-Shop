/**
 * 100 dedicated test phone numbers (+905550000000..+905550000099).
 * These are used exclusively by the load test harness.
 * setup.sh provisions these users and stores tokens in .tokens.json.
 */

const COUNT = 100;

export const TEST_PHONES = Array.from({ length: COUNT }, (_, i) =>
  `+9055500${String(i).padStart(5, '0')}`
);

/** Return the test phone for VU index n (wraps around). */
export function phoneForVU(n) {
  return TEST_PHONES[n % COUNT];
}
