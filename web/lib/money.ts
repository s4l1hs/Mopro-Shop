// Money utilities. All amounts are integer minor units (kuruş). Never use floats.

const TRY_FORMATTER = new Intl.NumberFormat("tr-TR", {
  style: "currency",
  currency: "TRY",
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

// Format minor units to locale string.
// For TRY_COIN, renders as "{amount} Coin" since it has no ISO 4217 code.
export function formatMinor(minor: number, currency: string): string {
  if (currency === "TRY_COIN") {
    return `${(minor / 100).toLocaleString("tr-TR", {
      minimumFractionDigits: 0,
      maximumFractionDigits: 2,
    })} Coin`;
  }
  return TRY_FORMATTER.format(minor / 100);
}

// Compact format for prices (e.g. ₺1.299 instead of ₺1.299,00)
export function formatPrice(minor: number, currency = "TRY"): string {
  if (currency === "TRY_COIN") {
    return `${Math.round(minor / 100).toLocaleString("tr-TR")} Coin`;
  }
  return new Intl.NumberFormat("tr-TR", {
    style: "currency",
    currency,
    minimumFractionDigits: minor % 100 === 0 ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(minor / 100);
}

// Client-side cashback preview (matches server formula).
// commission_minor = round(price * commission_pct_bps / 10000)
// yearly_yield = round(commission_minor * 5000 / 10000)  [reference_interest_rate = 5000 bps = 50%]
// monthly_coin = round(yearly_yield / 12)
// Inlined: monthly = round(price * commission_pct_bps / 156000)
export function cashbackMonthlyMinor(priceMinor: number, commissionPctBps: number): number {
  return Math.floor((priceMinor * commissionPctBps) / 156_000);
}
