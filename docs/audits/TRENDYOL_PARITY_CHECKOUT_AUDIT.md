# Trendyol Parity Audit — Checkout

> **Audit only — no code.** Self-audit of the Checkout flow vs a **provisional**
> Trendyol baseline (§2), seeded for Salih's walk. IDs **CHK-NN**, #09 walk format.
> `src` = Mopro code fact; `walk` = Salih's observation. **Checkout is
> auth-gated**, inherits **Cart**'s line-item/totals model, and shares a **backend
> cluster** with Cart (coupon CT-03 · basket-discount CT-09 · free-shipping CT-02 —
> build once, both surfaces benefit). Highest-stakes surface (money) — precise on
> payment / address / coin-redeem / order-summary totals.
>
> **Surface (source):** `CheckoutStepper` (3 steps) → `CheckoutAddressScreen` →
> `CheckoutPaymentScreen` → `CheckoutReviewScreen` → `CheckoutResultScreen`
> (+ `Checkout3dsWebviewScreen` / `SipayWebviewScreen` / `CheckoutRedirectScreen`).
> `checkoutControllerProvider` · `addressesProvider` · `cartProvider` (lines/totals).

---

## §0 — Legend

- **Source** — `src` (code fact) · `walk` (Salih). **Confidence** — **CONFIRMED**
  (structural src) · **PROBABLE** (visual/interaction — awaits walk) · **MATCHED**
  · **NOT-ACTIONABLE** (intentional). **Tags:** 🔗Cart-inherited · 🧩shared-backend-cluster.

---

## §1 — Summary

- **Checkout is built:** 3-step flow (address → payment → review) + stepper,
  address select/add/**default**, card (**3DS PSP-hosted**) + bank-transfer
  payment, **TR-legal consent** (distance-sales + pre-info) gating place-order,
  result/confirmation screen (order numbers, cashback note, clears cart), 3DS/Sipay
  webview redirect.
- **CONFIRMED gaps (src): 3** — CHK-01 review summary shows **total only** (no
  subtotal/shipping/KDV/cashback breakdown); CHK-02 **no per-seller grouping** in
  review (🔗 Cart); CHK-03 **no delivery options/slots** step.
- **🧩 Shared backend cluster (lands on cart + checkout): 3** — CHK-04 coupon
  (=CT-03), CHK-05 basket-discount (=CT-09), CHK-06 free-shipping (=CT-02).
- **PROBABLE (walk): 2** — CHK-07 saved-cards/installments, CHK-09
  validation/error states.
- **NOT-ACTIONABLE: 5** — coin-redeem-as-payment (**disabled, deferred IA-02**),
  cashback-earned note, PSP-hosted card entry, no installments (cashback is the
  analog), brand tokens.
- **Flow (§6):** reachable locally to the **payment/3DS** step (auth + cart +
  address); the PSP charge needs Sipay sandbox creds.

---

## §2 — Self-audit (Mopro current vs baseline)

| ID | Baseline (Trendyol) | Mopro current (`src`) | Delta | Status | Sev |
|---|---|---|---|---|---|
| — | Address: select saved + add + default | `CheckoutAddressScreen` — radio-select `addressesProvider`, `isDefault` badge, "add new" → `/profile/addresses/new`; empty-state CTA | — | **MATCHED** | — |
| — | Delivery options/slots per seller + cargo | — (no delivery step; shipping auto-computed in totals) | **no delivery slot/option selection** | **CHK-03** | MED |
| — | Payment: card + **saved cards** + **installments** + coin/wallet | `card` (→ **3DS Sipay webview**, PSP-hosted) · `bank_transfer` · `cashback` (**disabled**) | **no saved cards / no installments** (PSP-hosted; cashback is the Mopro analog) | **CHK-07** | PROBABLE |
| — | Order summary: lines + subtotal/shipping/coupon/basket-disc/KDV/cashback/**total** | `CheckoutReviewScreen` now renders the **full breakdown**: subtotal + shipping (free) + **total** + KDV note + monthly cashback (from `totals_by_seller`/`kdv_included` + `cartMonthlyCashbackProvider`) | **CHK-01 ✅ RESOLVED** (coupon/basket-disc still 🧩) | MED |
| — | Per-seller grouping carried from cart | review groups lines **by seller** (header = `seller_name` + per-seller subtotal) | **CHK-02 ✅ RESOLVED** | MED |
| — | Coupon/promo entry | — | absent (**= CT-03**) | **CHK-04** 🧩 | MED |
| — | "Sepette indirim" basket-discount line | — | absent (**= CT-09**) | **CHK-05** 🧩 | MED |
| — | Free-shipping threshold/progress | — | absent (**= CT-02**) | **CHK-06** 🧩 | LOW–MED |
| — | Consent (distance-sales + pre-info, TR legal) | **2 `_ConsentCheckbox`** (`consent_sales` + `consent_distance_contract`) gating place-order | — | **MATCHED** | — |
| — | "Siparişi Onayla" CTA + confirmation/success | place-order (consent-gated) → `placeOrder()`; `CheckoutResultScreen` (success/fail icon, order numbers, body, cashback note, continue-shopping, clears cart) | — | **MATCHED** | — |
| — | Coin/cashback redeem as payment | `cashback` method present but **`enabled: false`** | **disabled — deferred (IA-02 redeem)** | **NOT-ACTIONABLE** (D1) | — |
| — | Validation/error (missing address, payment fail, stock change) | result `failed` state; flow gates on address + consent | **stock-changed-at-checkout? error copy?** — walk | **CHK-09** | PROBABLE |

---

## §3 — Already-matched (VERIFIED from source)

3-step `CheckoutStepper` (address/payment/review) · address select + add +
**default** badge · **card via 3DS** (Sipay PSP-hosted) + **bank-transfer** ·
**TR-legal consent** (distance-sales + pre-info) gating place-order · place-order
CTA · **result/confirmation** (order numbers + success/fail + cashback note + cart
clear) · 3DS/Sipay/redirect webview flow · auth-gating (from cart).

---

## §4 — Intentional divergences (NOT-ACTIONABLE — do not flag)

- **D1 — Coin-redeem-as-payment** (`cashback` method) — Mopro's `coin_balance`
  payment divergence; currently **disabled / deferred (IA-02 redeem)**, not a
  parity gap.
- **D2 — Cashback-earned note** on the result screen (perpetual-cashback model).
- **D3 — PSP-hosted card entry** (3DS Sipay) instead of an in-app card form — a
  security choice, not a gap (also why "saved cards" needs PSP tokenization).
- **D4 — No installments** — Mopro's cashback is the analog (confirm in walk).
- **D5 — Brand-orange tokens.**

---

## §5 — Cart inheritance + 🧩 shared backend cluster

- **🔗 Cart-inherited:** the review uses `cart.lines` + `grandTotalMinor`. The
  **CHK-01 breakdown** + **CHK-02 per-seller grouping** are the *same* fixes as
  Cart's CT-04/CT-01 — the data (`totalsBySeller`) is already there; wire it into
  the review. (Cart's CT-01/CT-04 shipped in #173; the review didn't inherit them.)
- **🧩 Shared backend cluster — build once, both surfaces light up:**
  **coupon** (CT-03 / CHK-04), **basket-discount** (CT-09 / CHK-05),
  **free-shipping** (CT-02 / CHK-06). Each needs a backend (coupon engine,
  basket-discount surfacing, free-ship threshold) consumed by *both* the cart
  summary and the checkout review.

---

## §6 — Seed / flow (reachability for the walk)

- **Auth-gated + needs a cart + an address.** To reach checkout: log in (guest
  cart merges) → add-to-cart from the PDP → have/add a saved address
  (`/profile/addresses/new`). The walk can drive **address → payment → review**.
- **The PSP charge (3DS Sipay) needs sandbox creds** — the place-order/3DS
  completion isn't exercisable locally without Sipay sandbox config (flag). The
  **coin-redeem** path is disabled (IA-02) → not walkable.
- Caveat: per-seller grouping needs ≥2 sellers in the cart (achievable from seed).

---

## §7 — Walk-findings slots (Salih; #09 format)

> Walk: address select/add, payment-method UX, the review summary (breakdown? per
> seller?), consent copy, the 3DS hand-off, error states (failed payment, stock
> change). New items continue at **CHK-10+**.

```
### CHK-NN — <one-line title>
- **Surface/region:** Checkout › <address | delivery | payment | review/summary | consent | 3DS | result | errors>
- **Trendyol (live):** <observation>  [walk date: ____]
- **Mopro (current):** <file:line if known>
- **Delta / Status / Severity / Notes>
```

<!-- CHK-01 — confirm Trendyol's review shows the full totals breakdown. -->
<!-- CHK-07 — saved cards + installment rows. -->
<!-- CHK-09 — stock-changed-at-checkout + payment-failure copy. -->
<!-- CHK-10 … -->

---

## §8 — Prioritized fix list (after the walk)

1. **CHK-01 / CHK-02** — review summary breakdown + per-seller grouping. **Same
   fix as Cart CT-04/CT-01** (data in `totalsBySeller`); cheap, pays the money
   surface. 🔗
2. **🧩 Shared backend cluster (build once for cart + checkout):** coupon
   (CT-03/CHK-04), basket-discount (CT-09/CHK-05), free-shipping
   (CT-02/CHK-06). The biggest shared investment.
3. **CHK-03** — delivery options/slots per seller (backend + UI).
4. **CHK-07 / CHK-09** — saved cards / installments (PSP tokenization);
   validation/error copy — per the walk.

> **Coin-redeem (IA-02)** is a deliberate deferred divergence, not on this list.
> Severities provisional until the walk. No fixes in this PR.
