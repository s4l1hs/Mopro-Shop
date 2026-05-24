export const TR_PHONE_REGEX = /^\+905\d{9}$/;

/**
 * Normalize raw input to E.164 TR mobile format.
 * Accepts: plain 10-digit, leading-zero 11-digit, +90/90 prefixed 12-digit.
 * Returns "+905XXXXXXXXX" if valid, null otherwise.
 */
export function normalizeTrPhone(raw: string): string | null {
  const digits = raw.replace(/\D/g, "");
  let local: string;
  if (digits.length === 12 && digits.startsWith("90")) {
    local = digits.slice(2);
  } else if (digits.length === 11 && digits.startsWith("0")) {
    local = digits.slice(1);
  } else if (digits.length === 10) {
    local = digits;
  } else {
    return null;
  }
  if (!local.startsWith("5")) return null;
  return `+90${local}`;
}

/**
 * Format raw digit string for display: "5551234567" → "555 123 45 67".
 * Matches the Flutter _PhoneMaskFormatter space positions (3, 6, 8).
 * Handles partial input gracefully.
 */
export function formatTrPhoneForDisplay(digits: string): string {
  const d = digits.replace(/\D/g, "").slice(0, 10);
  let out = "";
  for (let i = 0; i < d.length; i++) {
    if (i === 3 || i === 6 || i === 8) out += " ";
    out += d[i];
  }
  return out;
}
