# Local walk environment — bring-up + full seed (reconstructed)

How to bring **current `main`** up locally with every surface seeded + a logged-in
test user, so the ten-surface parity walk is possible in one session. The previous
orchestrator (`scripts/dev/local-phaseb.sh`) was never merged to `main` and is gone
from disk — this doc + `scripts/dev/local-walk-seed.sh` replace it.

## Stack bring-up

- **Compose:** `make run-local` → `docker compose -f deploy/docker-compose.yml
  --env-file .env up -d --build`. `.env` lives in the repo root
  (gitignored; dev secrets — `JWT_SIGNING_KEY`, `PII_KEK_BASE64`, per-module DB
  passwords, `MARKET=TR`, `DEFAULT_LOCALE=tr-TR`, `PSP_PROVIDER=sipay`).
- **Services:** `core-svc` (:8080), `fin-svc` (:8081), `jobs-svc` (:8080) behind
  `caddy` on **:80**. Postgres `ecom`/`ledger` + pgbouncers + redis + meilisearch +
  minio. The Postgres containers are **internal-only** (no host port) — reach them
  with `docker exec postgres-ecom psql -U ecom_admin -d mopro_ecom`.
- **`--build` matters:** the running services were built from an older `main`;
  rebuild so the current handlers (e.g. OR-02 `delivery_address` on `GET /orders`,
  RT-01 refund-as-coin) exist.

## Caddy routing (no `/api` prefix)

`http://localhost/...` → `core-svc` by default; `/wallet/*`,`/cashback/*`,
`/payouts/*`,`/admin/*` → `fin-svc:8081`; `/jobs/*` → `jobs-svc`. Health: `/healthz`.

## Schema: init-scripts + migrations (the staleness trap)

The local DB schema comes from `deploy/postgres-{ecom,ledger}/init/*.sql`, run **once**
on a fresh volume — there is **no `schema_migrations` table** and the services do
**not** auto-migrate. So migrations added after a volume was created are NOT applied.

**Observed staleness (this refresh):** the running `ecom` DB had through ~0089
(`product_attributes` present) but was missing **0090–0093**: no
`order_schema.order_addresses` (0093), no `order_schema.coupons`/`coupon_redemptions`
(0092), no `order_items` basket-discount columns (0091), no `seller.is_official`
(0090). `ledger` was at ~0079 (missing the 0082 `equity:refund_distribution` account).

**Refresh = apply the pending `*.up.sql` directly** (they are additive —
`ADD COLUMN IF NOT EXISTS` / `CREATE TABLE IF NOT EXISTS` — so safe to psql in
order). `order_schema` has `ALTER DEFAULT PRIVILEGES`, so new tables created by
`ecom_admin` auto-grant to the app users. `scripts/dev/local-walk-seed.sh` applies
every `migrations/{ecom,ledger}/*.up.sql` above the detected high-water mark.

## Seeds (catalog already present; extras = SQL)

- **Catalog:** the Go seed CLI (`scripts/seed/cmd/seed`, `make seed-*`) populates
  `ref_schema.categories/commission_rules` + `catalog_schema` from `data/*.json`
  (50 products / 54 variants / 31 categories). **Already seeded** in the running DB
  (50/54/73). Idempotent (re-run = 0 writes).
- **SQL extras** (`scripts/seed/data/*.sql`, applied with `psql -f`):
  `merch-extras.sql` (bestseller/popularity signals), `coin-extras.sql`,
  `pdp-walk-extras.sql` (MP-S001 galleries + variants incl. OOS + `product_reviews`),
  `plp-density-extras.sql`, `attr-extras.sql` (renk/colour facets). Idempotent.
- The reviews table is `catalog_schema.product_reviews` (not `reviews`).

## Authed test user + their data

`identity_schema.users` was **empty**. Passwords are bcrypt-hashed and PII
(`email_enc`, `phone_enc`, address fields) is **AES-GCM-encrypted in the service**
(`PII_KEK_BASE64`) — so a raw-SQL user is wrong. Create the user + PII-bearing data
**through the live API**; use targeted SQL only for terminal states the API can't set.

**Auth flow (no email-verification gate):** `LoginEmail` blocks only
`Suspended`/`Deleted` — a freshly registered user logs in immediately.
1. `POST /auth/register` `{email,password,name_first,name_last,locale}` → 201.
2. `POST /auth/login` `{email,password}` → `{access_token, refresh_token}`.
3. Bearer the access token for the rest.

**Per-surface authed data + how it's seeded:**

| Data | Path | Notes |
|---|---|---|
| Addresses | `POST /me/addresses` (API) | PII-encrypted in-service; API only |
| Cart (multi-seller, discounts) | `POST /cart/items` (API) | variants chosen across ≥2 sellers; CT-09/coupon to show discount lines |
| Favorites | `POST /favorites` (API, raw-Dio) | hand-written endpoint, not codegen |
| Orders (varied status) | checkout flow → then SQL to set terminal `status` (`shipped/delivered/refunded`) | orders are created via checkout→payment; statuses past `paid` need a status nudge (no API to fast-forward delivery) |
| Returns (varied status) | `POST /orders/{id}/returns` (API) on a delivered order, then seller-approve / refund | needs a delivered order first |
| Coin balance + txns | **flows from cashback/refund**, not an admin grant | hardest: no `/admin` coin-credit endpoint; comes from a delivered order's cashback plan (cron mint) or an RT-01 refund. Documented as **partial** if not driven end-to-end. |

## Flutter → local backend, TR, logged in

- Base URL: the app's dev config points at `http://localhost` (the Caddy port).
  Confirm in `mobile/lib/core/config/*` / `--dart-define=API_BASE_URL=...`.
- Launch TR: `cd mobile && flutter run --dart-define=API_BASE_URL=http://localhost`
  (device/simulator/Chrome). Locale defaults to `tr-TR`.
- Log in with the seeded creds (below) on the auth screen, or print creds + steps
  for Salih to log in during the walk.

## Walk-readiness — see `WALK_READINESS.md` (generated by the seed script)
