# Manual Auth Flow Testing

Run `flutter test --no-pub` and `flutter analyze --no-pub` before each test session.

## Prerequisites

- Backend running locally or staging URL set via `--dart-define=API_BASE_URL=<url>`
- A Turkish phone number with SMS capability (or a test number configured in the backend)

## Steps

**1. Cold launch**
- Launch the app from scratch (no stored tokens).
- Expected: Splash screen appears briefly, then redirects to Phone Entry screen.

**2. Phone entry — empty state**
- Verify: `+90` prefix is visible and locked (non-editable).
- Verify: Submit button (`Kod Gönder` / `Send Code`) is **disabled** (greyed out).

**3. Phone entry — partial input**
- Enter fewer than 10 digits.
- Verify: Submit button remains disabled.

**4. Phone entry — valid input**
- Enter exactly 10 digits (e.g. `555 123 45 67`).
- Verify: Digits are formatted as `5XX XXX XX XX` with spaces.
- Verify: Submit button becomes **enabled**.

**5. OTP request**
- Tap Submit.
- Verify: Loading spinner appears on the button.
- Verify: Navigation to OTP screen with the correct phone number in the subtitle.
- Verify: 60-second resend countdown starts immediately.

**6. OTP screen — invalid code**
- Enter any 6-digit code that is incorrect.
- Verify: Error message appears below the OTP boxes with red tint on boxes.
- Verify: Submit button re-enables after error (user can retry).

**7. OTP screen — valid code**
- Enter the correct 6-digit OTP from SMS.
- Verify: Auto-submit fires when the 6th digit is entered.
- Verify: Navigation proceeds to home (`/`) if profile is already complete,
  or to Profile Completion screen if `name_first` is empty.

**8. Profile completion screen**
- Verify: Back gesture / back button is blocked (`PopScope(canPop: false)`).
- Enter a first name and last name.
- Verify: Submit button (`Complete Profile`) becomes **enabled** only when both fields are non-empty.
- Select a locale from the dropdown.
- Tap Submit.
- Verify: Navigation to home screen.

**9. Resend OTP**
- Return to OTP screen (or start fresh).
- Wait for the 60-second countdown to reach zero.
- Verify: `Resend` button appears.
- Tap Resend.
- Verify: Countdown resets to 60 seconds.
- Verify: A new OTP SMS is delivered.

**10. Rate-limit error (OTP exhausted)**
- Attempt to request or verify OTP more than 5 times in quick succession.
- Verify: `auth.rate_limit` error message displayed on the Phone or OTP screen.

**11. Phone locked error**
- Trigger the backend phone-lock threshold (backend config dependent).
- Verify: `auth.phone_locked` message displayed; Submit button disabled.

**12. Token refresh**
- Log in successfully.
- Wait for the access token to expire (or manually expire it via storage).
- Perform any authenticated action (e.g. navigate to a protected screen).
- Verify: The app silently refreshes the token and the action completes.

**13. Session revoked (token-family theft detection)**
- Trigger a `token_family_revoked` 401 response from the server (backend test endpoint or expired refresh-token family).
- Verify: A `SessionRevokedError` banner appears at the top of the screen for 6 seconds.
- Verify: User is redirected to the Phone Entry screen.
- Verify: Tokens are cleared from secure storage.

**14. Re-launch with valid tokens**
- Close and re-launch the app with a valid, non-expired access token in storage.
- Expected: Splash screen appears briefly, then redirects directly to home (`/`) without passing through auth screens.

---

## Phase 4.3b — Wallet + Cashback Timeline Screens

Run `flutter test --no-pub` and `flutter analyze --no-pub` before each test session.

### Prerequisites

- fin-svc running and reachable at `API_BASE_URL`
- Migration 74 applied (`deploy/postgres-ledger/init/74-cashback-payments-cursor-idx.sql`)
- Test data seeded (see below)

### Seed Test Data

```bash
# Connect to postgres-ledger and run:
./deploy/scripts/seed-test-wallet.sh
# Or with custom DSN:
LEDGER_DSN=postgres://ledger_admin:test123@localhost:6434/mopro_ledger \
  ./deploy/scripts/seed-test-wallet.sh
```

This seeds for `user_id=3`:
- Wallet account with 500,00 MC balance
- 1 cashback plan (`Sipariş #90001`, 50,00 MC/month, 90 days old)
- 3 paid payments + 3 scheduled payments

### Steps

**1. HomeScreen — CoinBalancePill appears**
- Log in as user_id=3 (phone: +905001234567 or whichever test account maps to id=3).
- Expected: CoinBalancePill appears at top of HomeScreen showing `"500,00 MC"` (or similar).
- Verify: Pill tappable — tap navigates to `/wallet`.

**2. WalletScreen — balance card**
- Expected: Balance card shows `"500,00 Mopro Coin"` (full format).
- Verify: Card background uses `colorScheme.primaryContainer`.

**3. WalletScreen — empty states (before seeding)**
- Before running the seed script, verify that "Henüz işlem yok" and "Henüz cashback planınız bulunmuyor." appear.

**4. WalletScreen — after seeding**
- Pull-to-refresh on WalletScreen.
- Verify: Cashback plan card appears ("Sipariş #90001").
- Verify: Product title in plan card shows fallback title (productId=0).

**5. PlanDetailScreen — navigation**
- Tap a plan card.
- Expected: Navigates to `/wallet/plans/<id>`.
- Expected: AppBar shows plan product title.
- Verify: PlanHeader shows `50,00 Mopro Coin` full format.
- Verify: "Süresiz plan" label visible.
- Verify: "Ödeme iptal edilene kadar her ay aktarılır." perpetual note visible.

**6. PlanDetailScreen — payment timeline**
- Expected: 6 timeline rows total (3 "Ödendi" + 3 "Planlandı").
- Verify: Paid rows have filled primary-colour dot.
- Verify: Scheduled rows have outlined/muted dot.
- Verify: Month labels are Turkish ("Ocak 2026", "Şubat 2026", etc.).

**7. Pull-to-refresh on PlanDetailScreen**
- Pull down.
- Expected: RefreshIndicator spinner appears, data reloads.
- Verify: No duplicate rows after refresh.

**8. Back navigation**
- From PlanDetailScreen, tap system back.
- Expected: Returns to WalletScreen.
- From WalletScreen, tap back.
- Expected: Returns to HomeScreen.

**9. Android back gesture (API 33+)**
- Use predictive back gesture.
- Expected: Correct screen transition without crash.

**10. Turkish locale formatting**
- With device locale set to tr-TR:
  - Amounts use `,` as decimal separator ("500,00 MC").
  - Month labels are Turkish ("Ocak", "Şubat", "Mart", etc.).

### Cleanup

```sql
DELETE FROM cashback_schema.payments
 WHERE idempotency_key LIKE 'test_visual_qa_%';
DELETE FROM cashback_schema.plans
 WHERE idempotency_key LIKE 'test_visual_qa_%';
```
