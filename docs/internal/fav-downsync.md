# Favorites down-sync + polish — FAV-02 / FAV-03 / FAV-04 (discovery)

> Make favorites sync **server→local** (cross-device) + two trivial fixes, per
> `TRENDYOL_PARITY_FAVORITES_AUDIT.md`. Local-verify; deploy deferred.

## State found (the FAV-02 gap)

- Favorites are a device-local `SharedPreferences` `Set<int>` (`FavoritesNotifier`,
  `favorites_provider.dart`). The grid hydrates them via `POST /products/batch`.
- **Sync is one-way (up only).** `POST /favorites/sync` (`handleFavoritesSync`,
  `home_handlers.go`, requireAuth, **raw `pool`**) upserts local→server into
  `catalog_schema.user_favorites` on login (`mergeGuestFavorites`, called from
  `AuthNotifier.setAuthenticated`). **There is no `GET /favorites`** → the mobile
  list never reads server state; `user_favorites` rows feed only the aggregate
  P-004 count. ⇒ no cross-device favorites.

## Discovery shifts

1. **Favorites are NOT in the OpenAPI spec — hand-written raw-Dio** (`/favorites/sync`,
   `/products/batch` both absent from `api/openapi.yaml`), exactly like the reviews
   endpoint (PD-07). So **GET /favorites is hand-written too** (consistent with its
   siblings) — **no spec/codegen change**; a **live-handler contract test** asserts
   the response shape directly (the PD-07 pattern). Forcing one favorites endpoint
   into the spec while sync/batch stay hand-written would be a half-migrated API —
   out of scope. (Drift gate is trivially in-sync; nothing regen'd.)
2. **`mergeGuestFavorites` (up-sync) lives in `features/cart/application/cart_merge_service.dart`**
   — **off-limits** (cart lane). So the down-sync hydration goes in a
   **favorites-owned** file (`favorites_provider.dart`), triggered from
   `core/auth/auth_notifier.dart` (touchable, not cart/checkout).
3. **Return IDs, not summaries.** The list already resolves products via
   `POST /products/batch` from the local `Set<int>`, so `GET /favorites` returns
   `{product_ids:[…]}`; the hydration merges them into the set and the existing
   batch path renders. Simplest + reuses the render path (escape-hatch §1.3).

## Plan (commit per concern)

1. **FAV-02 backend** — `GET /favorites` (requireAuth) → `{product_ids:[…]}`.
   §5-safe: a single `catalog_schema.user_favorites WHERE user_id=$1` query. To keep
   it **stub-testable** (the contract test can't drive a raw `*pgxpool.Pool`), the
   handler takes a narrow `favoritesReader` interface; `pgFavoritesReader{pool}` is
   the 6-line impl wired in `main.go`. (The write path `handleFavoritesSync` stays
   raw-pool — not touched; it's cart-adjacent.)
2. **FAV-02 mobile** — `FavoritesNotifier.mergeServer(ids)` (union, persists) +
   `hydrateFavoritesFromServer(ref)` (auth-interceptored Dio `GET /favorites`,
   best-effort) in `favorites_provider.dart`; call it after `mergeGuestFavorites`
   in `setAuthenticated` (post-login) and fire-and-forget in `build()` when already
   authed on launch.
3. **FAV-03** — `'Temizle'` → `favorites.clear_all`.tr() (en/tr).
4. **FAV-04** — favorites error state → a real retry (message + button), not the
   infinite `_SkeletonGrid`.
5. **Tests** — live-handler contract test for `GET /favorites` (stub
   `favoritesReader`); widget test for the retry state if cheap.
6. Audit (FAV-02/03/04 → resolved) + ledger.

§5: `user_favorites` is the source; product data resolves via the existing
batch/list path — no cross-schema JOIN. **FAV-01 collections (= P-013) deferred.**
