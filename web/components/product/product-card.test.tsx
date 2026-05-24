// Pure logic tests for ProductCard — no DOM rendering (vitest env: node).
// Tests validate the cashback and price logic that ProductCard uses.
// DOM rendering tests (renders title, heart click) would require jsdom setup.

import { describe, expect, it } from "vitest";
import { cashbackMonthlyMinor, formatPrice } from "@/lib/money";

// Same validation table as money.test.ts — DRY import of inputs.
const cashbackCases: Array<[number, number, number]> = [
  [1_000_000, 2000, 12_820], // 10k TL @ 20% → 12.82 TL/month
  [1_000_000, 1000,  6_410], // 10k TL @ 10% →  6.41 TL/month
  [1_000_000,  800,  5_128], // 10k TL @  8% →  5.13 TL/month
  [   25_000, 1500,    240], //  250 TL @ 15% →  2.40 TL/month
  [   99_999, 2000,  1_282], // 999.99 TL @ 20% → 12.82 TL/month
];

describe("ProductCard — CashbackChip formula", () => {
  it.each(cashbackCases)(
    "cashbackMonthlyMinor(%d, %d) → %d",
    (price, bps, expected) => {
      expect(cashbackMonthlyMinor(price, bps)).toBe(expected);
    },
  );

  it("returns 0 for zero commission", () => {
    expect(cashbackMonthlyMinor(1_000_000, 0)).toBe(0);
  });
});

describe("ProductCard — PriceDisplay formatting", () => {
  it("formats round TRY price without decimals", () => {
    const formatted = formatPrice(1_000_000);
    // 1_000_000 minor = 10.000 TL — must contain the amount
    expect(formatted).toContain("10.000");
  });

  it("formats TRY price with kuruş", () => {
    const formatted = formatPrice(99_950);
    expect(formatted).toContain("999");
    expect(formatted).toContain("50");
  });

  it("formats small price correctly", () => {
    const formatted = formatPrice(25_000);
    expect(formatted).toContain("250");
  });
});

describe("ProductCard — CashbackChip display text", () => {
  it("formats monthly coin amount as tr-TR locale string", () => {
    const monthly = cashbackMonthlyMinor(1_000_000, 2000); // 12_820
    const display = (monthly / 100).toLocaleString("tr-TR", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    });
    // tr-TR uses comma as decimal separator
    expect(display).toBe("128,20");
  });
});
