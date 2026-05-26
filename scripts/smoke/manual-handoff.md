# Manual UI Handoff Checklist — L9 Smoke (Web + Flutter)

**Instructions:**  
Work through each section against staging (`https://staging.moproshop.com` for web,
staging bundle for Flutter). Mark each item ✅ PASS, ❌ FAIL (with note), or
⚠️ STUB (known unimplemented — not blocking L9 unless noted otherwise).

**Tester:** ___________________  
**Date:** ___________________  
**Staging SHA:** ___________________  
**Environment:** Web browser: __________________ / Flutter build: __________________

---

## Section 1 — Cold Load + Theme

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 1.1 | Web: open `https://staging.moproshop.com` → loads in < 3s, no console errors | | |
| 1.2 | Web: tap dark/light theme toggle → theme switches instantly, no flash | | |
| 1.3 | Web: hard-reload (Ctrl+Shift+R) → page renders correctly from cache | | |
| 1.4 | Flutter: cold launch → splash screen, then home page in < 2s | | |
| 1.5 | Flutter: dark mode toggle in settings → persists after app restart | | |

---

## Section 2 — Auth — OTP Login

> Staging phone: **+90 555 123 4567** / OTP code: **123456** (bypass active)

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 2.1 | Enter phone +905551234567 → "Kod Gönderildi" / "Code Sent" confirmation | | |
| 2.2 | Enter code 123456 → lands on home page as authenticated user | | |
| 2.3 | Wrong code (e.g. 000000) → shows Turkish error message, does not log in | | |
| 2.4 | Log out → returns to login screen, session cleared | | |
| 2.5 | Re-login with same phone → works correctly | | |

---

## Section 3 — Home Page

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 3.1 | Banner carousel renders (or "coming soon" placeholder — not a blank area) | | |
| 3.2 | "Önerilen" / Recommended products section has ≥ 1 card | | |
| 3.3 | Tapping a product card navigates to the Product Detail Page (PDP) | | |
| 3.4 | Category pill row renders all 25+ seeded categories with icons | | |
| 3.5 | Tapping a category navigates to filtered product list | | |

---

## Section 4 — Catalog (Category Browse)

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 4.1 | Category page shows ≥ 1 product from seed data | | |
| 4.2 | Sort dropdown (Yeni → En Çok Satan, Fiyat) changes order | | |
| 4.3 | Scroll to bottom → loads more (infinite scroll or "Daha Fazla" pagination) | | |
| 4.4 | Empty category → renders "Bu kategoride ürün bulunamadı" message | | |
| 4.5 | Commission badge visible on each card (e.g. "%10 Komisyon") | | |

---

## Section 5 — Product Detail Page (PDP)

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 5.1 | Product images load; tapping opens full-screen viewer | | |
| 5.2 | Variant selector (size, color) — selecting a variant updates price | | |
| 5.3 | **Cashback preview is visible**: e.g. "Her ay X TL Mopro Coin kazan" | | |
| 5.4 | Cashback formula badge: monthly_coin = price × commission × 50% / 12 (spot-check 1 product) | | |
| 5.5 | "Sepete Ekle" adds the item to cart (cart icon badge increments) | | |
| 5.6 | Out-of-stock variant → "Stokta Yok" shown, add-to-cart disabled | | |
| 5.7 | Seller breakdown section shows: brüt, komisyon, KDV, net correctly | | |

---

## Section 6 — Search

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 6.1 | Search "kulaklik" → returns matching products from seed data | | |
| 6.2 | Empty search "" → shows placeholder / trending searches | | |
| 6.3 | Typo search "kulaklk" → ideally shows results (Meilisearch typo tolerance) | | |
| 6.4 | Search result card tap → navigates to PDP | | |

---

## Section 7 — Cart + Drawer

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 7.1 | Add 2 different products → both appear in cart drawer | | |
| 7.2 | Qty increment/decrement buttons work; total updates correctly | | |
| 7.3 | Remove item → item removed, total updates | | |
| 7.4 | Empty cart → "Sepetiniz boş" message + "Alışverişe Başla" CTA | | |
| 7.5 | Cart persists after app/browser restart (stored server-side via Redis) | | |

---

## Section 8 — Checkout (3 Steps + Sipay Sandbox)

> Use Sipay sandbox test card: **4111 1111 1111 1111**, expiry: **12/26**, CVV: **000**

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 8.1 | Step 1 — Address: pre-filled if saved, or add new address form works | | |
| 8.2 | Step 2 — Summary: shows itemised cart + per-seller commission breakdown visible | | |
| 8.3 | **Cashback preview visible on checkout summary**: "Bu siparişten X TL/ay Mopro Coin kazanacaksınız" | | |
| 8.4 | Step 3 — Payment: Sipay 3DS iframe/redirect loads with test card | | |
| 8.5 | Complete 3DS with test card → order confirmation screen shown | | |
| 8.6 | Order appears in /orders list with status "Sipariş Alındı" | | |
| 8.7 | Sipay webhook received → order status updated (verify in /orders/{id}) | | |
| 8.8 | **Cashback unlock date shown on order confirmation**: delivered_at + 3 business days | | |

---

## Section 9 — Order Confirmation + Detail

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 9.1 | Order detail page shows: order ID, items, amounts, estimated delivery | | |
| 9.2 | "Mopro Coin Kazanımı" section shows monthly coin amount and start date | | |
| 9.3 | Seller breakdown accessible from order (if seller panel tab exists) | | |
| 9.4 | Cancel order CTA visible for cancellable orders; works correctly | | |

---

## Section 10 — Account Area

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 10.1 | Profile page (`/me`): name, phone shown; edit works | | |
| 10.2 | Wallet balance: shows 0 TRY_COIN (new user, no cashback yet) | | |
| 10.3 | Cashback plans page: empty state message shown (no plan until order delivered) | | |
| 10.4 | Addresses list shows created address from section 4 | | |
| 10.5 | Logout: clears session, redirects to login | | |

---

## Section 11 — Cross-Platform Integration Checks

These five checks require a full end-to-end trace from payment to webhook to ledger.
Each is blocking for L9 certification.

| # | Check | Result | Notes |
|---|-------|--------|-------|
| **11.1** | **Happy path**: Real Sipay sandbox card (`4111...`) → captured webhook → order appears in `/orders` with `status=confirmed` | | |
| **11.2** | **Failed card**: Sipay declined card (use `4111 1111 1111 1119`) → checkout returns Turkish error "Ödeme başarısız. Lütfen tekrar deneyin." → no order created | | |
| **11.3** | **Mid-3DS cancel**: Start checkout, reach 3DS page, tap Back/Cancel → no order created, cart items preserved, no stale reservation | | |
| **11.4** | **Webhook race**: Webhook arrives before 3DS return URL completes → order still confirmed correctly (both paths are idempotent via idempotency_key) | | |
| **11.5** | **Delayed webhook** (simulate): After 3DS success, if webhook delayed → order shows `payment_pending` → after webhook delivered within 60s, auto-updates to `confirmed` (or reconciler picks up) | | |

---

## Summary

| Section | Status | Notes |
|---------|--------|-------|
| 1. Cold Load + Theme | | |
| 2. Auth | | |
| 3. Home Page | | |
| 4. Catalog | | |
| 5. PDP | | |
| 6. Search | | |
| 7. Cart | | |
| 8. Checkout | | |
| 9. Order Confirmation | | |
| 10. Account | | |
| 11. Integration Checks | | |

**Overall UI verdict:** ☐ PASS  ☐ PASS WITH CAVEATS  ☐ FAIL

**Known stubs / caveats:**
- 
- 

**Blocking issues (must fix before L9 PASS):**
- 
- 

**Tester sign-off:** ___________________  **Date:** ___________________
