/**
 * Token cache loader.
 * Reads .tokens.json (written by setup.sh) and .otps.json (written by run.sh
 * immediately before each test run for the S2 OTP-verify scenario).
 *
 * All open() calls are relative to the load-tests/ CWD where k6 is invoked.
 */
import { SharedArray } from 'k6/data';

// ── Token cache ───────────────────────────────────────────────────────────────

const _tokens = new SharedArray('tokens', function () {
  try {
    const raw = JSON.parse(open('../.tokens.json'));
    return Object.entries(raw).map(([phone, token]) => ({ phone, token }));
  } catch (_) {
    return [];
  }
});

/**
 * Return {phone, token} for this VU.
 * VUs cycle through the pool so each VU gets a consistent identity.
 */
export function getAuth() {
  if (_tokens.length === 0) {
    throw new Error('No tokens loaded. Run setup.sh first.');
  }
  return _tokens[__VU % _tokens.length];
}

// ── Fresh OTP cache (for S2 — refreshed by run.sh right before the test) ──────

const _otps = new SharedArray('otps', function () {
  try {
    return JSON.parse(open('../.otps.json'));
  } catch (_) {
    return [];
  }
});

/**
 * Return {phone, code} for this VU.
 * Returns null when .otps.json was not pre-populated by run.sh.
 */
export function getOTP() {
  if (_otps.length === 0) return null;
  return _otps[__VU % _otps.length];
}
