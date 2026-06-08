# IA-02 — Coin hub page (discovery)

> Build the Coin hub behind IA-01's Coin tab: balance, earn/spend history,
> ways-to-earn, redeem — on Mopro's real coin ledger. **Outcome C: ship the
> read-only hub (balance + history + ways-to-earn); DEFER redeem** — there is no
> discrete, idempotent redeem endpoint, and the only coin-spend model is the
> checkout `coin_balance` payment method (a payment flow, out of scope §1.2/§7.6).
> Never half-build a financial mutation (§5).

## What the backend exposes (it's almost all there)

- **Balance** — `GET /wallet/balance` → `WalletBalance {currency, amount_minor,
  last_updated_at}` (`internal/api/fin_impl.go:GetWalletBalance`). Resolves the
  caller's wallet account via `WalletSvc.FindAccountByOwnerAnyStatus("user",
  userID, currency)` → `GetBalance(acctID)`; currency defaults to `TRY_COIN`;
  0 when no wallet exists. **wallet_schema only — no cross-schema JOIN (§5 ✓).**
- **History** — `GET /wallet/transactions` (cursor-paginated) →
  `WalletTransaction {id, type: credit|debit, amount_minor, currency,
  description, reference_id, reference_type: cashback_payment|payout|adjustment,
  occurred_at}`. `type` gives the earn(credit)/spend(debit) sign; `occurred_at`
  the date. Reads `wallet_schema` ledger entries (§5 ✓).
- **Cashback plans** — `GET /cashback/plans` (+ `/{id}`, `/{id}/payments`) →
  perpetual plans. These ARE the "ways to earn": each active plan pays
  `monthly_amount_minor` coins/month forever.
- **Redeem** — **none.** `coin_balance` exists ONLY as a generated checkout
  payment-method enum (`CheckoutRequestPaymentMethodType`); no discrete
  redeem/convert/withdraw endpoint, no coin-spend mutation owned by a hub. The
  real "spend" model is *pay with coins at checkout* — a payment flow, explicitly
  out of scope (§1.2, §7.6). Building a new redeem mutation = inventing a coin
  model (§0/§1.3 forbid). → **DEFER.**

## The mobile already has most of this

`mobile/lib/features/wallet/` ships a `WalletScreen` (route `/wallet`, in the
account shell) that renders **balance card + transactions + cashback plans** via
`walletProvider` (`getWalletBalance` / `listWalletTransactions`) and
`cashbackPlansProvider`. Widgets: `_BalanceCard`, `transaction_tile`,
`plan_card`. **So the coin hub = reuse these real-ledger providers/widgets, add a
ways-to-earn section + a redeem-deferred ("coming soon") affordance, behind the
Coin tab.** No new backend, no client regen.

## Ledger model (so the hub reads truth)

Coins live in `postgres-ledger` `wallet_schema`: `accounts`
(owner_type/owner_id/currency/status/type), `transactions`, `ledger_entries`
(double-entry, append-only, DEFERRABLE balance trigger). A user's coin wallet =
`liability` account `owner_type='user', owner_id=<uid>, currency='TRY_COIN'`.
Cashback credits = `C` to that account (per CLAUDE.md §4.7). Balance = the
account balance; transactions = its ledger entries. All wallet_schema-internal.

## financial-core conventions that apply

Read-only hub → mostly read conventions: **#3 soft-deleted-user guard** (lives in
`WalletSvc` already — reused, not bypassed), **#7 soft refs / no cross-schema
JOIN** (wallet queries are wallet_schema-only; `reference_id` is a soft ref to a
plan/payout, NOT joined). The mutation conventions (**#1 SERIALIZABLE, #2
pool-acquire, #4 idempotency, #5 outbox**) would govern **redeem** — which is
exactly why it's DEFER'd until a real, idempotent, ledger-correct model exists.
The dev **seed** writes balanced double-entry transactions (**§4.1**), honoring
the ledger invariants rather than fabricating a balance.

## Guest-gating

Coins are per-user (a guest has no wallet). `/wallet` is `hardGated` (redirect to
login) in the router; but `/coin` is a **tab** — a redirect-on-tap is jarring.
Use a **soft in-screen gate** (`features/auth/widgets/login_required.dart` /
`core/widgets/login_required_sheet.dart` + `authNotifierProvider`): guests see a
"log in to see your coins" state; authed users see the hub. Dev login works via
`DEV_OTP_ACCEPT_ANY=true` (.env.local).

## Dev seed

`scripts/dev/local-phaseb.sh` seeds catalog (ecom) only — no coin data. Extend it
(or a `home-extras`-style ledger SQL) to credit a fixed dev user's `TRY_COIN`
wallet with a few **balanced** transactions (D `equity:cashback_distribution:
TRY_COIN` ↔ C `liability:wallet:user_<id>:TRY_COIN`) + refresh the balance, so the
hub renders against real ledger rows. Log in as that user on the emulator.

## Plan (Outcome C)

1. This doc.
2. **Mobile `CoinHubScreen`** at `/coin` (replaces IA-01's `CoinScreen`
   placeholder): balance header + history (earn/spend, signed, dated) + ways-to-
   earn (from active plans) + redeem "coming soon" (DEFER); reuse wallet+cashback
   providers/widgets; soft guest-gate; loading/empty/error; i18n TR+EN.
3. **Dev seed:** balanced coin credits for a dev user (ledger-correct, §4.1).
4. **Goldens:** predict (`/coin` is new → likely a new coin-hub golden if added)
   + Linux regen.

**DEFER'd:** discrete redeem (no idempotent ledger-correct model; coin-spend =
checkout `coin_balance`, a payment flow) → its own PR. No backend reads added
(they exist); no spec/client change.
