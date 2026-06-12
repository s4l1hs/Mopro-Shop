# Trendyol Parity Audit — Account (Hesabım)

> **Audit only — no code.** Self-audit of the Account hub vs a **provisional**
> Trendyol baseline (§2), seeded for Salih's walk. IDs **AC-NN**, #09 walk format.
> Sibling of the Cart/PDP/PLP/Search/Favorites audits. `src` = Mopro code fact;
> `walk` = Salih's visual/interaction observation. Account is **auth-gated** (guest
> sees a register/login prompt).
>
> **METHODOLOGY (the headline) — read-path reality check.** Every section is rated
> not just "does a widget exist" but **does the backend actually serve it**:
> **L = LIVE** (real backend read-path) · **S = STUB** (UI exists, no working
> backend / dead handler) · **U = UI-only** (client-only, no backend needed). This
> corrects the cart audit's mistake (UI marked "matched" over a stub backend). It
> caught **2 dead entries** here that a UI-only pass would have passed.
>
> **Surface (source):** `account_screen.dart` (mobile hub) + `account_left_rail` /
> `account_right_pane` / `account_shell` (desktop two-pane) · sub-screens
> `profile_screen` · `cards_screen` · `security_screen` · `privacy_settings_screen`
> · `my_reviews_screen` · `my_questions_screen` · `browsing_history_screen` ·
> `wallet/` (coin hub). Providers: `current_user_provider`, `ordersProvider`,
> `walletProvider`, `cashbackPlansProvider`.

---

## §0 — Legend

- **Read-path** — **L** live · **S** stub (UI over no/dead backend) · **U** UI-only
  (no backend needed).
- **Confidence** — **CONFIRMED** (source fact) · **PROBABLE** (visual/interaction —
  awaits walk) · **MATCHED** · **NOT-ACTIONABLE** (intentional divergence).

---

## §1 — Summary

- **The hub is overwhelmingly LIVE** — unlike the cart, the read-path check **passed**
  for 13 of 15 sections (real backends: `/me`, `/orders`, fin-svc wallet, `/addresses`
  CRUD, `/me/reviews`, `/me/questions`, `/me/password`+`/auth/mfa`, `/me/consent`,
  `/me/recently-viewed`).
- **2 STUBS the read-path check caught (a UI-only audit would have missed):**
  - **AC-01 Saved Cards (S)** — `cards_screen` always renders `cards.empty` + the
    add-card flow is `// TODO(mopro): wire to add card flow`. No list, no add.
  - **AC-02 Help — ✅ RESOLVED** (`feat/quick-functional-gaps`): the dead
    `onTap: () {}` now routes to the existing `/help` (`HelpIndexScreen`).
- **2 CONFIRMED gaps (src):** **AC-03** no email-change in Security (password +
  phone/MFA only); **AC-04** no notification-preferences setting.
- **AC-05 → ✅ RESOLVED (phase 1)** (`feat/membership-tier`; Salih decided to build the tier). Design-first (`docs/internal/membership-tier.md`): tier = *status* loyalty coexisting with the coin model behind a hard wall — a pure derived read-model (no ledger/balance/minting). Shipped: `ref_schema.membership_tiers` ladder (migration 0094, classic/gold/elite TR, AND-ed spend+orders thresholds, 365-day window) + `order.MembershipService` (§5-safe: own-schema aggregate + ref read; ReturnService-style separate interface) + `GET /me/membership` (spec/codegen, contract-tested both shapes) + Account badge/progress card (binding-constraint progress). **Later phases (design doc):** money benefits (free shipping / tier discounts / multipliers) = financial follow-ups (§4); benefit enforcement across surfaces.
- ~~**PROBABLE (await walk): 1**~~ (original) — **AC-05** no membership tier/points display. *(Resolved above.)*
- **NOT-ACTIONABLE: 3** — the Coin/cashback wallet hub (vs Trendyol coupons/wallet),
  coin+plans stats (vs Elite tier/points), brand-orange tokens.

---

## §2 — Self-audit (Mopro current vs baseline) — with read-path

| Section | Trendyol baseline | Mopro current (`src`) | Read-path | Delta / Status | Sev |
|---|---|---|---|---|---|
| **Header / profile** | name, photo, membership level/points | `/me` (name) + 3 stat tiles (active orders, **coin**, active **plans**) | **L** (`GET /me` + orders/wallet providers) | **AC-05** no membership tier/points (coin+plans instead — divergence) | LOW |
| **My Orders** | entry → orders | `→ /orders` | **L** (`GET /orders`) | **MATCHED** (orders gets its own audit) | — |
| **Coin / cashback wallet** | coupons + wallet | `→ /wallet` coin hub (balance + plans + transactions) | **L** (fin-svc `GetWalletBalance` → `WalletSvc.GetBalance`; `ListWalletTransactions`; plans) | **NOT-ACTIONABLE** (Mopro coin-model hub — IA-02) | — |
| **Favorites** | entry → favorites | `→ /favorites` | **L** (`/favorites` two-way sync, FAV-02) | **MATCHED** | — |
| **Addresses** | saved-address CRUD | `→ /profile/addresses` | **L** (`GET/POST/PUT/DELETE /addresses` → `identity.Service`) | **MATCHED** | — |
| **Payment methods / saved cards** | saved cards CRUD | `cards_screen` | **S** | **AC-01** UI-only: always `cards.empty` + add-card is a TODO. PSP-hosted model (cards entered at PSP checkout, not stored) softens it, but the section is a dead stub | MED |
| **Reviews I've written** | my reviews | `→ /account/reviews` | **L** (`GET /me/reviews`) | **MATCHED** | — |
| **Questions I've asked** | my Q&A | `→ /account/questions` | **L** (`GET /me/questions`) | **MATCHED** | — |
| **Security** | password, 2FA, email/phone | `security_screen` | **L** (`GET /me`, `POST /me/password`, `/auth/mfa` enroll/confirm) | **AC-03** password + phone/MFA present; **no email-change** path | LOW–MED |
| **Privacy / consent** | (KVKK) | `privacy_settings_screen` | **L** (`GET/PUT /me/consent`, `DELETE /me/analytics-data`) | **MATCHED** (Mopro PLUS: data-deletion) | — |
| **Browsing history** | recently viewed | `browsing_history_screen` | **L** (`GET /me/recently-viewed`) | **MATCHED** | — |
| **Help / support** | help center + tickets | hub Help entry → `/help` (`HelpIndexScreen`) | **L** | **AC-02 ✅ RESOLVED** — the dead `onTap: () {}` now routes to the existing `/help` route (`feat/quick-functional-gaps`) | — |
| **Settings — appearance** | theme | theme light/dark/system toggle | **U** (client) | **MATCHED** | — |
| **Settings — language** | language | `account.language` (desktop rail) | **U** (easy_localization) | **MATCHED** (mobile-hub placement — confirm on walk) | — |
| **Settings — notifications** | push/email prefs | — | **—** | **AC-04** no notification-preferences setting | LOW–MED |
| **Logout** | logout | clears tokens | **U** (client) | **MATCHED** | — |

---

## §3 — The read-path check, distilled

> **13 LIVE / 2 STUB / —.** The hub passes the reality check far better than the
> cart did. The **two stubs (AC-01 cards, AC-02 help)** are the audit's real output —
> both are **UI-over-no-wired-backend** (cards: empty + TODO; help: dead `onTap`),
> exactly the class the cart audit missed by trusting widgets. Everything else
> reads a real backend (verified to the handler/`WalletSvc` call). **AC-02 is the
> cheapest real fix** (a backend exists; just wire the button). AC-01 needs a card
> vault decision (or a "managed at checkout" empty-state copy, given PSP-hosted).

---

## §4 — Intentional divergences (NOT-ACTIONABLE — do not flag)

- **D1 — Coin/cashback wallet hub** in place of Trendyol's coupons + wallet (the
  perpetual-cashback business model; IA-02).
- **D2 — Header stats are coin + active-plans**, not an Elite membership tier/points.
- **D3 — Brand-orange tokens.**
- **D4 — PSP-hosted cards** (cards entered at the PSP during checkout, not stored by
  Mopro) — the *model* is intentional; the dead **cards_screen** stub (AC-01) is the
  flagged part, not the PSP choice.

---

## §5 — Walk slots (Salih, logged-in)

1. **Header** — name + the 3 stat tiles (orders/coin/plans); confirm vs Trendyol's
   membership block (AC-05).
2. **Each entry taps through** — Orders, Wallet, Favorites, Addresses, Reviews,
   Questions, Profile, Security, Privacy, Browsing history all reach a real screen.
3. **AC-01 Saved Cards** — confirm it's an empty stub (no list, no add).
4. **AC-02 Help** — confirm the Help entry does nothing (dead button).
5. **AC-03 Security** — confirm password + phone/MFA but **no email change**.
6. **AC-04** — confirm no notification-preferences screen.
7. **Guest state** — logged-out hub shows the register/login prompt.

---

## §6 — Prioritized fix list (after the walk) — stubs first

1. **AC-02 Help (stub)** — wire the hub Help entry to the existing
   `internal/help`/`internal/support` backend (cheapest — backend already exists).
2. **AC-01 Saved Cards (stub)** — either a card-vault list/add (PSP token vault) or
   a "cards are managed at checkout" empty-state (given PSP-hosted) — a product
   decision, not just UI.
3. **AC-03 / AC-04** — email-change in Security; notification-preferences setting.
4. **AC-05** — membership/tier block (only if Mopro adopts a tier concept; else
   NOT-ACTIONABLE — the coin hub is the analog).

> **Status: SEEDED — awaiting Salih's walk.** Read-path **L/S** ratings are CONFIRMED
> from source; Trendyol-side deltas (AC-05 etc.) firm up on the walk.
