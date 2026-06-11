# Checkout PROBABLE resolution — source-side pass (not a visual walk)

Home method: Mopro from code (fact) × Trendyol convention (provisional, ~May 2025,
*not visually verified*).

### CHK-07 — no saved cards / no installments → NOT-ACTIONABLE (settled divergence)
- **Mopro (fact):** payment = `card` (→ **3DS Sipay webview, PSP-hosted**),
  `bank_transfer`, `cashback` (disabled). No saved-card tokenization; no installments.
- **Trendyol (provisional):** saved cards + installments *(convention)*.
- **Verdict:** **NOT-ACTIONABLE** — card entry is **PSP-hosted** (no card data on
  Mopro to tokenize), and installments are a **PSP/business-model** feature for which
  the **perpetual cashback is the Mopro analog**. Both are settled divergences (§5.3 —
  not re-opened on a guess).

### CHK-09 — validation/error states (stock-changed, payment-fail copy) → NEEDS-VISUAL
- **Mopro (fact):** the flow gates on address + consent and surfaces a generic
  `failed` result state; there's no dedicated/bespoke copy for every edge (e.g.
  "stock changed at checkout").
- **Trendyol (provisional):** specific validation/error copy per edge *(convention)*.
- **Verdict:** a generic failed state exists; whether the **error copy reads well /
  covers the edges** is exactly an **eyes-on** judgment (and a "stock-changed-at-
  capture" path would also need backend re-validation). → **NEEDS-VISUAL** (Salih).
  Not guessed.

## Outcome

| Row | Verdict |
|---|---|
| CHK-07 saved cards / installments | **NOT-ACTIONABLE** (PSP-hosted + cashback analog — settled) |
| CHK-09 validation/error states | **NEEDS-VISUAL** (error-copy coverage/feel) |

**0 CONFIRMED fixes.** The Checkout NOT-ACTIONABLE set already records coin-redeem
(deferred IA-02), cashback-earned note, PSP-hosted card entry, no-installments.

## Salih's residue (Checkout)
- **NEEDS-VISUAL:** CHK-09 — checkout error/validation copy (does the failed-state
  copy read well + cover stock-changed/payment-fail?).
