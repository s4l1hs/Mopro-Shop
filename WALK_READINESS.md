# Walk readiness — local env on current `main`

Refreshed for the ten-surface Trendyol parity walk. Backend rebuilt from current
`main`, both DBs migrated to head, all seeds applied, and a logged-in test user
with cart / favorites / addresses / orders / returns / coin.

## Login (the walk user)

| | |
|---|---|
| **Email** | `walk@mopro.local` |
| **Password** | `WalkTest1234!` |
| **Base URL** | `http://localhost` (Caddy; no `/api` prefix) |

Email-verification is flipped in-DB by the seed (login otherwise 403s
`email_not_verified`). To launch the app pointed at local, TR locale:

```bash
cd mobile && flutter run --dart-define=API_BASE_URL=http://localhost
# then log in with the creds above (locale defaults to tr-TR)
```

Re-seed any time (idempotent): `scripts/dev/local-walk-seed.sh` (stack must be up
via `make run-local`).

## Per-surface readiness

| # | Surface | Renders with data | How to reach / notes |
|---|---|---|---|
| 1 | **Home** | ✅ yes | `/home/rails` (recommended / Çok satanlar / Yeni gelenler) + banners + flash-deals; 50 products + popularity signals seeded |
| 2 | **PLP / category** | ✅ yes | tap a category; 50 products, attributes/facets (renk), bestseller + price signals |
| 3 | **PDP** | ✅ yes | open product **#15** (MP-S001) — 5 variants (incl. OOS), per-variant galleries (5/4/3/4/4 images), 7 reviews |
| 4 | **Search** | ✅ yes | search e.g. "kalem"; Meilisearch-backed, relevance + filters |
| 5 | **Cart** | ✅ yes | 3 items across **multiple sellers** (products spread to sellers 2 & 3); enriched lines + `totals_by_seller` |
| 6 | **Favorites** | ✅ yes | 4 favorited products (#1, #3, #5, #9) |
| 7 | **Account** | ✅ yes | logged-in profile + **2 addresses** (Ev default, İş) |
| 8 | **Orders** | ✅ yes | **6 orders across all 5 statuses**: pending_payment, paid, shipped, delivered (×2), refunded; detail enriches item title/price |
| 9 | **Returns** | ✅ yes | **3 returns across 3 statuses**: pending, approved, refunded (exercises the RT-06 status filter + RT-04 history) |
| 10 | **Wallet / Coin** | ✅ yes (see note) | non-zero `TRY_COIN` balance + transaction; **note:** the `/wallet/balance` endpoint reads a materialized balance — the seed's balanced ledger entry posts to `ledger_entries` (visible to the strict/live balance + history) while the headline balance reflects the account's existing materialized total. Both are non-zero, so the surface walks. |

## Checkout (needs cart + address — both seeded)

Checkout is reachable from the cart: the user has a **populated multi-seller cart**
and a **default address**, so the checkout review/address/payment steps render. The
order is created via the checkout→payment flow (the seeded orders above are
history; placing a *new* order exercises the live flow end-to-end).

## What's partial / synthetic (per §1.3)

- **Coin balance** is the only "partial": a real balance flows from the cashback
  engine (delivered-order → plan → monthly mint) or an RT-01 refund, not an admin
  grant. The seed posts one balanced `equity:cashback_distribution → wallet`
  entry; the headline (materialized) balance is non-zero regardless. Driving it
  fully would mean running the cashback cron against the seeded delivered orders.
- **Order/return economics are illustrative** (15% commission / 20% KDV snapshots),
  seeded by direct SQL for terminal statuses the API can't fast-forward to
  (delivered/refunded). They render correctly; they are not the product of a real
  payment+delivery flow.
- **Catalog discounts** (`products.basket_discount_pct`) exist on 5 products after
  migration 0087 — the cart/PLP "Sepette %X" pill shows where those products are.

## Backend bugs fixed to get here

- `jobs-svc` crash-looped on `Europe/Istanbul` (no `time/tzdata` embed on
  distroless) — fixed (would also fail in prod).
- migration `0091` had a stray `</content>` tag (broke `migrate-tool up`) — stripped.

See `docs/internal/local-walk-env.md` for the full bring-up + staleness story.
