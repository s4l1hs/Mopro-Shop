# L9c — Manual Residual Checklist

**Scope:** Everything in `scripts/smoke/manual-handoff.md` that Playwright E2E **cannot** deterministically automate — requires human eyes, a real payment card, or a live Flutter device.

**Estimated time:** 60–90 minutes total  
**Prerequisites:**
- Staging stack healthy (`make health-check` green)
- Seed data present (`make seed-staging`)
- Sipay sandbox card: `4111 1111 1111 1111` / 12/26 / CVV 000
- Sipay sandbox declined card: `4111 1111 1111 1119` / 12/26 / CVV 000
- Flutter build installed on test device (iOS Simulator or Android Emulator)
- Staging SHA visible at `https://api-staging.moproshop.com/__version`

**Cross-reference:** `docs/launch/L9-smoke-report-4e73f254617c.md` (definitive PASS report)  
**Automated coverage:** `web/e2e/` — run `pnpm test:e2e --reporter=list` first; all passing before starting this checklist.

---

## Section A — Flutter Full Pass (~25 min)

These checks are Flutter-native and outside Playwright's scope.

| # | Check | Result | Notes |
|---|-------|--------|-------|
| F1 | Flutter cold launch → splash screen appears, then home page loads in < 2s | | |
| F2 | Dark mode toggle in Flutter Settings → theme switches; persists after app restart (kill + reopen) | | |
| F3 | OTP login in Flutter: phone `+905551234567`, code `123456` → authenticated home | | |
| F4 | Flutter product detail page: cashback preview shows "Aylık X TL Mopro Coin" with correct amount | | |
| F5 | Flutter cart: add product, verify cart badge increments; cart persists after backgrounding | | |
| F6 | Flutter checkout — 3-step flow: address → summary → Sipay WebView loads | | |
| F7 | Flutter 3DS: enter test card `4111 1111 1111 1111` in Sipay WebView → order confirmation screen | | |
| F8 | Flutter order list: placed order appears with status "Sipariş Alındı" | | |
| F9 | Flutter account: Cashback tab shows plan created from F7 order (after ~5 min for delivery simulation) | | |
| F10 | Flutter account: Addresses page shows address added during checkout | | |

**Flutter verdict:** ☐ PASS  ☐ FAIL  ☐ PARTIAL

---

## Section B — Web Visual / UX (~15 min)

Items that require human visual judgment beyond `toBeVisible()`.

| # | Check | Result | Notes |
|---|-------|--------|-------|
| V1 | Banner carousel on home page: images render correctly (no broken img placeholders); auto-advances | | |
| V2 | Product card: commission badge ("%X Komisyon" or cashback chip) is visually distinct, not clipped | | |
| V3 | PDP: image gallery full-screen viewer — tap image → full-screen overlay opens, swipe to next works | | |
| V4 | PDP: variant selector (size/color) — selecting a variant updates price and stock status in < 500ms | | |
| V5 | PDP: out-of-stock variant → "Stokta Yok" button shown, disabled (cannot click) | | |
| V6 | PDP: seller breakdown section renders brüt / komisyon / KDV / net values correctly | | |
| V7 | Checkout Step 2 summary: per-seller commission breakdown visible, amounts match PDP preview | | |
| V8 | Order confirmation page: cashback unlock date is displayed as a human-readable date string | | |
| V9 | `/account/cashback`: active plans list each show `plan_id`, `monthly_amount`, `start_date` | | |

**Visual verdict:** ☐ PASS  ☐ FAIL  ☐ PARTIAL

---

## Section C — Sipay 3DS Real-Card Payment (~20 min)

Manual-handoff.md §8.4–8.8 + §11.1 full.

> Use Sipay sandbox cards only. Never use real card numbers on staging.

| # | Check | Result | Notes |
|---|-------|--------|-------|
| C1 | Web checkout Step 3: Sipay 3DS iframe or redirect page loads (no blank white page) | | |
| C2 | Enter card `4111 1111 1111 1111` / 12/26 / 000 in Sipay form → complete 3DS simulation | | |
| C3 | After 3DS success → redirected to `/checkout/redirect?status=success` or order confirmation | | |
| C4 | Order appears in `/account/orders` with status "Sipariş Alındı" or "Ödeme Onaylandı" | | |
| C5 | Order detail `/account/orders/{id}`: shows itemised amounts + cashback unlock date | | |
| C6 | Declined card `4111 1111 1111 1119` → Sipay returns decline → web shows Turkish error "Ödeme başarısız. Lütfen tekrar deneyin." | | |
| C7 | After declined card: cart items are still intact (no phantom cart clear) | | |
| C8 | Sipay webhook in logs: `grep "sipay webhook" /var/log/mopro/core-svc.log` shows captured event within 60s | | |

**Payment verdict:** ☐ PASS  ☐ FAIL  ☐ PARTIAL

---

## Section D — Edge Cases + Accessibility (~10 min)

| # | Check | Result | Notes |
|---|-------|--------|-------|
| E1 | Mid-3DS cancel: reach Sipay 3DS page, click browser Back → `/checkout/redirect?status=cancelled` → cart preserved | | |
| E2 | Keyboard navigation: Tab through home → login → OTP → home without mouse (WCAG 2.1 AA basic) | | |
| E3 | Mobile viewport (375×812): home page, PDP, and cart are usable without horizontal scroll | | |
| E4 | Arabic/English locale `/en/` prefix: open `https://staging.moproshop.com/en/` → page renders in English | | |
| E5 | `/__version` SHA: `curl https://api-staging.moproshop.com/__version` returns SHA matching current `git rev-parse HEAD` | | |

**Edge verdict:** ☐ PASS  ☐ FAIL  ☐ PARTIAL

---

## Section E — Bug Filing Protocol

If any check above fails:

1. **Capture:** screenshot + browser console logs + VDS logs (`docker compose logs core-svc --tail=50`)
2. **File:** create issue in GitHub Issues with label `bug`, `staging`, `l9c`
3. **Title format:** `[L9c] Section X.N — <short description>`
4. **Blocking threshold:** Any C-section (Sipay) failure or F7/F8 failure is **L9c blocking** — do not proceed to L10 until resolved.
5. **Non-blocking:** V-section visual polish, E2/E3 accessibility gaps are non-blocking for L9c but must be tracked.

---

## Sign-Off

| Section | Status | Tester | Date |
|---------|--------|--------|------|
| A — Flutter | | | |
| B — Visual/UX | | | |
| C — Sipay 3DS | | | |
| D — Edge/A11y | | | |

**L9c overall verdict:** ☐ PASS  ☐ PASS WITH CAVEATS  ☐ FAIL

**Tester:** ___________________  **SHA:** ___________________  **Date:** ___________________

Proceed to `docs/launch/L10-production-cutover-plan.md` only after all sections are PASS or PASS WITH CAVEATS.
