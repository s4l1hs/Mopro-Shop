import { describe, expect, it } from "vitest";
import { SIPAY_ERROR_MESSAGES, getSipayErrorMessage } from "./error-map";

const knownCodes = Object.keys(SIPAY_ERROR_MESSAGES).filter((k) => k !== "unknown");

describe("SIPAY_ERROR_MESSAGES — completeness", () => {
  it("has at least 10 known error codes", () => {
    expect(knownCodes.length).toBeGreaterThanOrEqual(10);
  });

  it("every entry is a non-empty Turkish string", () => {
    for (const [code, msg] of Object.entries(SIPAY_ERROR_MESSAGES)) {
      expect(msg.length, `code "${code}" has empty message`).toBeGreaterThan(0);
    }
  });
});

describe("getSipayErrorMessage — known codes", () => {
  const cases: Array<[string, string]> = [
    ["insufficient_funds", "bakiye"],
    ["card_declined", "ret"],
    ["3ds_failed", "3D Secure"],
    ["invalid_card", "hatalı"],
    ["expired_card", "süresi dolmuş"],
    ["cvv_mismatch", "CVV"],
    ["issuer_unavailable", "Banka"],
    ["fraud_suspected", "Güvenlik"],
    ["amount_limit_exceeded", "limit"],
    ["rate_limit_exceeded", "dakika"],
  ];

  it.each(cases)("code '%s' → message contains '%s'", (code, contains) => {
    const msg = getSipayErrorMessage(code);
    expect(msg.toLowerCase()).toContain(contains.toLowerCase());
  });
});

describe("getSipayErrorMessage — fallback behaviour", () => {
  it("returns unknown message for unrecognised code", () => {
    expect(getSipayErrorMessage("totally_unknown_xyz")).toBe(
      SIPAY_ERROR_MESSAGES.unknown,
    );
  });

  it("returns unknown message for null", () => {
    expect(getSipayErrorMessage(null)).toBe(SIPAY_ERROR_MESSAGES.unknown);
  });

  it("returns unknown message for undefined", () => {
    expect(getSipayErrorMessage(undefined)).toBe(SIPAY_ERROR_MESSAGES.unknown);
  });

  it("returns unknown message for empty string", () => {
    expect(getSipayErrorMessage("")).toBe(SIPAY_ERROR_MESSAGES.unknown);
  });
});
