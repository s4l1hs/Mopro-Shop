# Flutter L1 Manual QA Checklist

> **Purpose:** Complete manual QA pass before every release build.
> **Backend:** Staging (`https://api-staging.moproshop.com`), seeded by L2 (31 categories, 50 products).
> **How to use:** Copy this file, fill in the result table, tick boxes as you go. File a GitHub issue for every failed assertion using `.github/ISSUE_TEMPLATE/qa-bug.md`.

---

## Result

| Date | Build SHA | APK version | iOS version | Tester | Pass count | Fail count |
|------|-----------|-------------|-------------|--------|------------|------------|
| YYYY-MM-DD | `abc1234` | 0.x.0 | 0.x.0 | name | N/M | K |

---

## Setup

### 1. Build & Install

```bash
# Android (debug APK)
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk

# iOS (simulator, macOS only)
flutter build ios --debug --simulator
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted com.mopro.shop

# Point the app at staging (via .env or build arg)
# ensure lib/config/env.dart has BACKEND_URL = "https://api-staging.moproshop.com"
```

### 2. Test Credentials

| Field | Value |
|-------|-------|
| Test phone | `+90 555 111 22 33` |
| OTP bypass code | `123456` |
| Wrong OTP (for error test) | `999999` |
| Luhn-invalid card | `4111 1111 1111 1112` |
| Luhn-valid Visa test | `4111 1111 1111 1111` |
| Luhn-valid Mastercard | `5500 0000 0000 0004` |
| Troy test | `9792 0300 0000 0009` |
| Amex test (4-digit CVV) | `3782 822463 10005` |
| Force-fail card | `4000 0000 0000 0002` |

### 3. Device Matrix

Run the checklist on **both** devices. Mark `[A]` (Android) or `[i]` (iOS) next to any assertion that fails on only one platform.

| # | Device | OS | Status |
|---|--------|----|--------|
| Primary | Pixel 6 emulator | Android 14 (API 34) | required |
| Secondary | iPhone 15 simulator | iOS 17 | required on macOS |

### 4. Cashback Formula Reference

All cashback values in the app are computed from `internal/cashback.CashbackK = 156 000`. All arithmetic is **integer (truncating) division** — no rounding, no floats.

```
T (total months)   = 156 000 ÷ commission_pct_bps   (truncated integer)
M (monthly coin)   = price_minor × bps ÷ 156 000    (truncated integer, kuruş)
M_last (balloon)   = price_minor − (T − 1) × M      (always ≥ M)

Invariant: (T − 1) × M + M_last = price_minor  (exact, no rounding leak)
```

**BPS → T quick reference** (use when verifying PDP cashback card):

| commission_pct_bps | T (months) | Category examples |
|--------------------|-----------|-------------------|
| 500 | 312 | Kitap (roman, eğitim) |
| 700 | 222 | Elektronik (akıllı telefon, kamera) |
| 750 | 208 | Tablet |
| 800 | 195 | Bilgisayar/Laptop |
| 900 | 173 | Kulaklık, bisiklet |
| 1 000 | 156 | Spor (fitness, top) |
| 1 200 | 130 | Ev (mutfak), outdoor |
| 1 500 | 104 | Ev dekorasyon, moda aksesuar, spor giyim |
| 1 800 | 86 | Ev tekstil, kozmetik parfüm, moda ayakkabı |
| 2 000 | 78 | Moda giyim (kadın/erkek), kozmetik cilt bakım |

**Worked example — MP-E006 Akıllı Telefon (₺64 999.00, bps = 700):**

```
T        = 156 000 ÷ 700    = 222 months
M        = 6 499 900 × 700 ÷ 156 000 = 29 166 kuruş = ₺291.66
M_last   = 6 499 900 − 221 × 29 166  = 54 214 kuruş = ₺542.14
Check    = 221 × 29 166 + 54 214      = 6 499 900  ✓
```

---

## 1. Cold Start + Theme (5 checks)

```
Precondition: fresh install, system dark mode OFF.
```

- [ ] App launches and the home screen renders in **light mode** without any flash or incorrect initial theme.
- [ ] In Account → Settings, the theme toggle cycles through **System → Light → Dark → System** in order with each tap.
- [ ] Selecting **Dark** and performing a cold restart (fully kill + reopen) shows the app still in dark mode — theme preference is persisted.
- [ ] The splash screen (Mopro logo + background) renders correctly in **light mode** — no clipped assets, correct brand colour.
- [ ] The splash screen renders correctly in **dark mode** — no clipped assets, background adjusts to dark variant.

---

## 2. Auth — OTP Login (8 checks)

```
Precondition: logged-out state (or fresh install).
```

- [ ] Entering fewer than 10 digits in the phone field and tapping "Devam et" shows an inline validation error; no network request is fired.
- [ ] Entering more than 10 digits is rejected by the field (input capped at 10 or submission blocked with error); no network request is fired.
- [ ] Entering `+90 555 111 22 33` (10 digits without prefix, or with prefix) and tapping "Devam et" fires `POST /auth/otp/request` → app transitions to the OTP entry screen showing a success state ("Kod gönderildi").
- [ ] The OTP input accepts up to 6 digits; submitting a 5-digit code (e.g., `12345`) does not auto-advance and shows an error.
- [ ] Entering the wrong OTP `999999` and confirming shows an **inline error** ("Hatalı kod") without navigating away from the OTP screen.
- [ ] Entering the bypass OTP `123456` and confirming navigates to the **home screen**; no error state is shown.
- [ ] After successful login, an auth-state inspector (e.g., Flutter DevTools → State, or in-app debug overlay) shows the `mopro_s` (session token) flag as non-empty.
- [ ] **Refresh token rotation:** log in, background the app for at least 16 minutes, then return. The app is still authenticated (silent token refresh succeeded); no forced re-login prompt appears.

---

## 3. Home Screen (10 checks)

```
Precondition: logged in, staging seed loaded.
```

- [ ] The hero carousel **auto-rotates** to the next slide approximately every 5 seconds without user interaction.
- [ ] Exactly **4 slides** are visible in the carousel; the progress dot indicator updates to match the active slide index.
- [ ] Tapping the CTA button on any carousel slide navigates to the expected destination (category page or product detail); use the back button to return and verify for at least 2 different slides.
- [ ] The category quick-grid shows **exactly 8 tiles**; each tile displays the correct label and icon/illustration.
- [ ] Tapping a category tile navigates to `/categories/${slug}` (verify the route in the address bar via Flutter DevTools or proxy).
- [ ] **"Senin için seçtiklerimiz"** horizontal rail loads and displays ≥ 6 product cards without error.
- [ ] **"Çok satanlar"** horizontal rail loads and displays ≥ 6 product cards without error.
- [ ] **"Yeni gelenler"** horizontal rail loads and displays ≥ 6 product cards without error.
- [ ] The **trust bar** (icons + micro-copy below hero or above footer) shows exactly 4 items (e.g., ücretsiz iade, güvenli ödeme, hızlı teslimat, alıcı koruması).
- [ ] **Pull-to-refresh** (drag down on the home scroll view) triggers a reload spinner; all rails refresh their data.

---

## 4. Catalog List (8 checks)

```
Precondition: navigate to any leaf category that has seeded products (e.g., "Akıllı Telefon").
```

- [ ] Opening the category shows **≥ 1 product card** immediately; no empty-state illustration appears.
- [ ] Tapping the filter icon opens the **filter bottom sheet**; the sheet scrolls smoothly through all filter groups without jank.
- [ ] Setting price range **min = 500, max = 2500** and applying reduces the visible product count compared to unfiltered results (verify the count badge in the filter button updates).
- [ ] Selecting a single **brand** in the brand filter applies it; all visible product cards belong to that brand.
- [ ] Enabling **"Cashback ≥ %20"** filter shows only products whose `commission_pct_bps ≥ 2000` (moda giyim + kozmetik categories at staging seed rates); products from other categories disappear.
- [ ] Sort → **"Fiyat Artan"**: verify the first card's price is ≤ the last visible card's price; sort → "Fiyat Azalan" reverses the order.
- [ ] **Pagination**: scroll to the end of the first page; the next page loads automatically (infinite scroll) or via a "Daha fazla" button; navigating back restores the same scroll position.
- [ ] Applying filters, navigating away, and pressing back (or refreshing via deeplink) **preserves the active filter + sort state** — product list and filter badge reappear as before.

---

## 5. Product Detail Page (12 checks)

```
Precondition: open the PDP for MP-E006 (Akıllı Telefon, ₺64 999.00, bps = 700)
for the cashback assertion; use other seeded products for stock assertions.
```

- [ ] **Image gallery**: swiping left/right cycles through all product images; swipe indicators (dots or counter) update correctly.
- [ ] Tapping an image opens a **full-screen dialog**; pinch-to-zoom in/out works and the image does not clip or overflow.
- [ ] **Brand**, **product title**, **star rating** (numeric), and **review count** all render in their designated positions; none are truncated unexpectedly.
- [ ] **Cashback card** displays monthly coin amount and total months. For MP-E006: verify **M = ₺291.66 / ay** and **T = 222 ay**. For a 2000-bps product: **T = 78 ay**. See §Setup for the full BPS table.
- [ ] Tapping **"Nasıl çalışır?"** on the cashback card opens an explanatory bottom sheet or modal; the sheet closes cleanly with the back gesture.
- [ ] **Stock indicator** reflects seed data: a product seeded with `stock > 10` shows "Stokta var"; a product seeded with `stock ∈ [1, 5]` shows "Son N adet"; a product seeded with `stock = 0` shows "Tükendi" and the add-to-cart button is disabled.
- [ ] The **quantity stepper** on an in-stock product caps at 10; on a low-stock product it caps at the actual `stock_qty`; the stepper cannot decrement below 1.
- [ ] After scrolling past the hero section, the **sticky purchase bar** (price + "Sepete Ekle") remains fixed at the bottom of the screen.
- [ ] Tapping **"Sepete Ekle"** for an in-stock product: (a) fires `POST /cart/items`, (b) a snackbar appears with a "Sepete git" action button, (c) the cart tab badge increments.
- [ ] Tapping **"Sepete git"** in the snackbar navigates directly to the cart tab without going through home.
- [ ] The **"Açıklama"** tab renders the product description text; the **"Özellikler"** tab renders the specs JSONB data seeded in `product_translations.specs` (at least 2 key-value rows visible).
- [ ] The **related products rail** at the bottom of the PDP loads ≥ 1 product card from the same category; tapping a card navigates to that product's PDP.

---

## 6. Search (5 checks)

```
Precondition: open the search screen for the first time (no prior searches).
```

- [ ] The initial search screen shows either "Son aramalarınız" (empty state) and/or a **"Önerilen Kategoriler"** grid of tiles.
- [ ] Typing a query (e.g., "telefon") causes results to **begin appearing after the debounce** (≈ 300 ms pause after typing stops); the screen does not show a full-page spinner during typing.
- [ ] Searching for a term guaranteed to return no results (e.g., "xyznonexistent") shows a **"{q} için sonuç bulunamadı"** empty state plus at least one suggestion chip or CTA.
- [ ] After successfully completing a search, the term appears in the **recent searches list**; this list persists after a cold restart of the app.
- [ ] Tapping the **X chip** next to a specific recent search removes only that entry; the remaining entries are unchanged.

---

## 7. Cart (8 checks)

```
Precondition: add at least 2 different products from different BPS categories.
```

- [ ] The **cart tab badge** shows the correct total item count after adding products; it updates immediately without a reload.
- [ ] Each **cart line item** displays: product image, title, variant (color/size if applicable), and the price **snapshotted at add-time** (not re-fetched live).
- [ ] Adjusting quantity via the stepper updates both the **line subtotal** and the **estimated monthly cashback** for that line in real time.
- [ ] **Swipe-to-delete** on a line item removes it; the cart total and cashback estimate update immediately.
- [ ] **Manual math verification**: for each line item compute `monthly_estimate = price_minor × bps ÷ 156 000 × qty` (truncated integer); verify the cart's displayed total monthly coin equals the sum across all lines.
- [ ] After removing all items, the **empty-cart illustration** and a "Alışverişe Başla" CTA appear.
- [ ] **Cold restart persistence**: add items, kill the app completely, reopen — the cart still shows the same items.
- [ ] Attempting to set a line item quantity **above the available stock** shows an inline warning and caps the quantity at the seeded stock value.

---

## 8. Checkout — 3 Steps (14 checks)

### Step 1 — Address

```
Precondition: at least one saved address exists, or use the add-address flow below.
```

- [ ] The address list screen loads all saved addresses from `GET /addresses` without error.
- [ ] **Add new address**: opening the "Yeni adres ekle" sheet — entering a phone number shorter than 10 digits blocks submission; the city dropdown populates all 81 Turkish provinces; tapping "Kaydet" creates the address and it appears in the list.
- [ ] **Edit existing address**: opening an existing address in edit mode, changing a field, and saving persists the change — the updated value appears in the list immediately.
- [ ] The **"Devam et"** button on Step 1 is **disabled** (greyed, non-tappable) until at least one address is selected.

### Step 2 — Payment

- [ ] The payment method radio group **defaults to "Kredi/Banka kartı"**; any future payment methods (e.g., installment, wallet) are rendered but greyed/disabled.
- [ ] Entering the Luhn-invalid card number `4111 1111 1111 1112` and attempting to proceed shows a **card number validation error** before any network request.
- [ ] Card brand auto-detection: `4111 1111 1111 1111` shows the **Visa** icon; `5500 0000 0000 0004` shows **Mastercard**; `9792 0300 0000 0009` shows **Troy**.
- [ ] CVV field for Visa/Mastercard enforces **exactly 3 digits**; for Amex (`3782 822463 10005`) it enforces **exactly 4 digits**.
- [ ] The **"Devam et"** button on Step 2 is **disabled** until all required card fields (number, expiry, CVV, name) pass validation.

### Step 3 — Review & Confirm

- [ ] The order review screen displays the selected **address**, the **masked card** (last 4 digits), all **line items** with quantities, the **subtotal**, and the **estimated monthly cashback**.
- [ ] Both **"Mesafeli Satış Sözleşmesi"** and **"Ön Bilgilendirme Formu"** checkboxes must be ticked; "Siparişi Onayla" is **disabled** until both are checked.
- [ ] Tapping **"Siparişi Onayla"** fires `POST /orders`; observe in the HTTP proxy (e.g., mitmproxy or Charles) that the response body contains a non-empty `order_id`.
- [ ] The **3DS stub WebView** launches after order creation (stub mode — confirm the stub page renders visible content, not a blank white screen or crash).
- [ ] The **deep-link callback** from 3DS returns the user to `/orders/:id?status=success`; the order confirmation screen is shown.

---

## 9. Order Confirmation + Detail (8 checks)

```
Precondition: complete a successful checkout with the Luhn-valid Visa test card.
```

- [ ] The **success screen** displays the order number and the **cashback activation date** ("Cashback başlangıç tarihi"), which equals delivery date + 3 business days per the TR calendar.
- [ ] The **cart is empty** after the success screen is shown; navigating to the cart tab shows the empty-cart illustration.
- [ ] **Failure path**: complete checkout with the force-fail card `4000 0000 0000 0002`; the failure screen shows a human-readable reason text and a **"Tekrar dene"** CTA that returns to the payment step.
- [ ] `GET /account/orders` list shows the **newly placed order** at the top, with correct order number, date, and status.
- [ ] The order detail **timeline** renders exactly 4 steps: Ödeme Alındı → Hazırlanıyor → Kargoya Verildi → Teslim Edildi; the active step is visually distinct.
- [ ] The **cashback schedule section** in the order detail shows exactly **T rows** where T = 156 000 ÷ bps for the order's category (e.g., T = 222 for an Elektronik order, T = 78 for a moda giyim order).
- [ ] The **final row** (installment #T) is visually distinct and labeled **"Balon ödeme"**; its amount (M_last) is ≥ M from all preceding rows.
- [ ] **Rounding invariant**: sum all T coin amounts displayed in the schedule; the total must equal the order item's `price_minor` exactly (zero deviation). Use a calculator to verify.

---

## 10. Account Area (15 checks)

```
Precondition: logged in; at least one order placed in this session.
```

- [ ] Account **dashboard** shows 4 stat cards (Toplam sipariş, Toplam harcama, Aktif cashback planı, Cüzdan bakiyesi) — all show non-zero / non-null data after the test order is placed.
- [ ] **Sidebar navigation**: tapping each entry (Siparişlerim, Cashback, Cüzdan, Adresler, Profil, Güvenlik, Kartlarım, Favorilerim) navigates to the correct screen with no blank-state flicker.
- [ ] The **cashback wallet hero** on the Cashback screen shows the total monthly coin amount that matches the placed test order's M value.
- [ ] The **cashback chart** (bar or area graph) renders without pixel overflow or RenderFlex error in both **light** and **dark** themes.
- [ ] The cashback **history tab pagination** loads the next page when scrolling to the bottom; navigating back to the list restores the previous scroll position.
- [ ] The **"Katkı sağlayanlar"** accordion expands to reveal contributing orders and collapses back cleanly; expanded state does not persist across navigations.
- [ ] **Addresses flow (all 4 operations)**: add a new address → it appears in the list; edit a field → change saved; delete it → it is removed; set-default → the star/default badge moves to the correct address.
- [ ] **Profile — TC kimlik validator**: entering `12345678901` (fails Luhn-style checksum) shows a validation error; entering a valid 11-digit TC identity number (use an algorithmically valid test number, e.g., `10000000146`) passes validation.
- [ ] **Security — Hesabımı Sil**: the sessions list loads showing at least the current session; the "Hesabımı sil" button reveals a confirmation dialog that requires typing `MOPRO` before the confirm button activates.
- [ ] **Cards tab** shows the empty-state illustration ("Henüz kart eklemediniz") since no saved cards have been added in this test session.
- [ ] **Favorites — add**: tapping the heart icon on a product card in any listing adds it to the Favorilerim list; the list is visible immediately.
- [ ] **Favorites — remove**: tapping the active heart again removes the product from the list; the list updates immediately.
- [ ] **Profile photo stub**: tapping "Fotoğraf yükle" opens the system image picker (or a permission dialog); the app does not crash or freeze (backend upload is stubbed — picker opening is sufficient).
- [ ] **Notification settings**: all toggle switches render and respond to taps; toggled state persists after a cold restart (local persistence only — backend sync is stubbed).
- [ ] **Logout**: tapping "Çıkış yap" and confirming clears the session token, empties the cart, and redirects the app to the `/login` screen; attempting to deep-link to a protected route sends back to `/login`.

---

## Known Stubs

The following items are **intentionally not fully implemented** at L1. Do **not** file bug reports for them unless the stub itself crashes or shows a blank white screen.

| Stub | Expected behaviour in testing |
|------|-------------------------------|
| **Sipay 3DS WebView** | Renders a stub HTML page; "Ödemeyi Onayla" button triggers the success deep-link callback |
| **`POST /cart/validate`** | Endpoint may return 200 with no body (noop); cart proceeds regardless |
| **`GET /account/summary`** | May return mocked JSON; stat card values may be static |
| **`GET /cashback/*`** (wallet balance, history) | May return mocked data; zero balance is acceptable |
| **Favorites backend sync** | Favorites stored in device `SharedPreferences` only; not synced to server |
| **"Fotoğraf yükle"** (profile photo upload) | Opens picker; no upload occurs; no error expected |
| **"Yeni kart ekle"** in Cards tab | Tapping opens a sheet or navigates; no tokenization request expected |
| **Değerlendirmeler tab** in PDP | May show empty state ("Henüz değerlendirme yok") |
| **Soru & Cevap tab** in PDP | May show empty state |
| **Notification settings backend sync** | Toggle state saved locally only; no `PATCH /notifications/preferences` fired |

---

## Bug Reporting

If an assertion fails, file a GitHub issue using the **[QA Bug template](./../../../.github/ISSUE_TEMPLATE/qa-bug.md)**.

**Required fields:**

| Field | Where to find it |
|-------|-----------------|
| Build SHA | `git rev-parse --short HEAD` in the repo |
| APK version | `version:` in `pubspec.yaml` |
| Device | emulator name + OS version |
| Repro steps | numbered from fresh install |
| Expected vs actual | quote the exact assertion from this doc |
| Screenshot / recording | mandatory for any UI assertion |

**Severity guide:**

- **Blocker** — user cannot complete the affected flow; must fix before release cut.
- **Major** — incorrect behaviour but a workaround exists; fix in the same release if time allows.
- **Minor** — cosmetic or UX issue; log, triage in next sprint.

**Label your issue:** `bug` + `qa` + the flow label (e.g., `flow:checkout`, `flow:pdp`).

---

## Assertion Count Summary

| Flow | Checks |
|------|--------|
| 1. Cold Start + Theme | 5 |
| 2. Auth — OTP Login | 8 |
| 3. Home Screen | 10 |
| 4. Catalog List | 8 |
| 5. Product Detail (PDP) | 12 |
| 6. Search | 5 |
| 7. Cart | 8 |
| 8. Checkout — 3 Steps | 14 |
| 9. Order Confirmation + Detail | 8 |
| 10. Account Area | 15 |
| **Total** | **93** |
