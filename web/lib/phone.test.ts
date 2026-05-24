import { describe, expect, it } from "vitest";
import { formatTrPhoneForDisplay, normalizeTrPhone, TR_PHONE_REGEX } from "./phone";

describe("normalizeTrPhone", () => {
  it("happy path — plain 10 digits starting with 5", () => {
    expect(normalizeTrPhone("5551234567")).toBe("+905551234567");
  });

  it("with spaces — '555 123 45 67'", () => {
    expect(normalizeTrPhone("555 123 45 67")).toBe("+905551234567");
  });

  it("with country code — '+90 555 123 45 67'", () => {
    expect(normalizeTrPhone("+90 555 123 45 67")).toBe("+905551234567");
  });

  it("too long — '+90 555 123 45 67 888' → null", () => {
    expect(normalizeTrPhone("+90 555 123 45 67 888")).toBeNull();
  });

  it("doesn't start with 5 — '1234567890' → null", () => {
    expect(normalizeTrPhone("1234567890")).toBeNull();
  });

  it("empty string → null", () => {
    expect(normalizeTrPhone("")).toBeNull();
  });

  it("non-digit garbage → null", () => {
    expect(normalizeTrPhone("abc")).toBeNull();
  });

  it("too short — '5551234' → null", () => {
    expect(normalizeTrPhone("5551234")).toBeNull();
  });

  it("leading-zero format — '05551234567'", () => {
    expect(normalizeTrPhone("05551234567")).toBe("+905551234567");
  });

  it("90-prefixed without + — '905551234567'", () => {
    expect(normalizeTrPhone("905551234567")).toBe("+905551234567");
  });
});

describe("formatTrPhoneForDisplay", () => {
  it("full 10 digits → spaced format", () => {
    expect(formatTrPhoneForDisplay("5551234567")).toBe("555 123 45 67");
  });

  it("partial — 5 digits", () => {
    expect(formatTrPhoneForDisplay("55512")).toBe("555 12");
  });

  it("partial — 3 digits", () => {
    expect(formatTrPhoneForDisplay("555")).toBe("555");
  });

  it("partial — 4 digits", () => {
    expect(formatTrPhoneForDisplay("5551")).toBe("555 1");
  });

  it("empty → empty", () => {
    expect(formatTrPhoneForDisplay("")).toBe("");
  });

  it("strips non-digit characters", () => {
    expect(formatTrPhoneForDisplay("555-123-45-67")).toBe("555 123 45 67");
  });

  it("truncates at 10 digits", () => {
    expect(formatTrPhoneForDisplay("55512345678888")).toBe("555 123 45 67");
  });
});

describe("TR_PHONE_REGEX", () => {
  it("matches valid E.164 TR mobile", () => {
    expect(TR_PHONE_REGEX.test("+905551234567")).toBe(true);
  });

  it("rejects landline-style (non-5 prefix)", () => {
    expect(TR_PHONE_REGEX.test("+902121234567")).toBe(false);
  });

  it("rejects too-long number", () => {
    expect(TR_PHONE_REGEX.test("+9055512345678")).toBe(false);
  });

  it("rejects missing + prefix", () => {
    expect(TR_PHONE_REGEX.test("905551234567")).toBe(false);
  });
});
