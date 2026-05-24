/**
 * UUID v4 generator for Idempotency-Key headers.
 * Must be called per request — never re-use a key.
 */
import crypto from 'k6/crypto';

export function newIdempotencyKey() {
  const bytes = new Uint8Array(crypto.randomBytes(16));
  // Set version 4 and variant bits per RFC 4122
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join('-');
}
