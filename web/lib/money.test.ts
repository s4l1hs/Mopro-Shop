import { describe, it, expect } from 'vitest';
import { cashbackMonthlyMinor } from './money';

describe('cashbackMonthlyMinor', () => {
  // Validation table from Phase 2.2 spec — MUST match backend exactly.
  // Backend source of truth: internal/cashback/calculator.go (CashbackK = 156000)
  const cases: Array<[number, number, number]> = [
    // [priceMinor, commissionBps, expectedMonthlyMinor]
    [1_000_000, 2000, 12_820], // 10k TL @ 20% → 12.82 TL/month
    [1_000_000, 1000,  6_410], // 10k TL @ 10% →  6.41 TL/month
    [1_000_000,  800,  5_128], // 10k TL @  8% →  5.13 TL/month
    [   25_000, 1500,    240], //   250 TL @ 15% →  2.40 TL/month
    [   99_999, 2000,  1_282], // 999.99 TL @ 20% → 12.82 TL/month
  ];

  it.each(cases)('priceMinor=%d, bps=%d → %d', (price, bps, expected) => {
    expect(cashbackMonthlyMinor(price, bps)).toBe(expected);
  });
});
