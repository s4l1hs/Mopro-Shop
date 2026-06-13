# FAV-07 — "fiyatı düştü since favorited" indicator

> Lane `feat/fav-07`. Completes the deferred favorites price-drop cue per
> `TRENDYOL_PARITY_FAVORITES_AUDIT.md` + `favorites-probable-resolution.md`.
> Local-verify; deploy deferred.

## Audited scope (re-read)

- **Audit (`favorites-probable-resolution.md` §FAV-07):** *No "fiyatı düştü since
  favorited" cue. Favorites store only IDs — no price-at-favorite snapshot — so the
  only price signal is the card's generic lowest-30d strikethrough, not a "dropped
  since you saved it" cue.* Verdict: **DEFER — needs a price-at-favorite snapshot
  (favorites schema/data change + per-item compare).**
- **Deliverable:** a per-favorite "fiyatı düştü" badge on the favorites surface that
  fires when the **live** price is below the price the user saw **when they
  favorited** the item — independent of the card's generic lowest-30d strikethrough.

## Discovery shift — backend/data → **FE-only**

The audit tagged FAV-07 "DEFER (backend/data)" on the assumption a price-at-favorite
snapshot must live in a favorites **schema**. Walking the real ownership model flips
that:

- Favorites are a **device-local `SharedPreferences` `Set<int>`** (`FavoritesNotifier`,
  `favorites_provider.dart`). The server `catalog_schema.user_favorites` holds **only
  IDs** as a union backup (FAV-02 down-sync, `GET /favorites` → `{product_ids:[…]}`);
  the up-sync (`POST /favorites/sync` / `mergeGuestFavorites`) is **cart-owned**
  (`cart_merge_service.dart`, off-limits per `fav-downsync.md`) and carries only IDs.
- The price-at-favorite is captured **at the moment the user toggles the heart** — a
  client event. The client already renders the price at that instant (`ProductCard`,
  PDP). So the faithful, real-source snapshot lives **client-side**, exactly where
  favorites themselves live.
- A server snapshot would (a) need migration 0105 + a new column, (b) require plumbing
  the price through the cart-owned sync request (off-limits) and the GET response, and
  (c) still miss **guest** favorites (deliberately local, no auth wall). It would be a
  half-measure for marginal cross-device value.

⇒ **Footprint: FE-only.** No migration, no codegen, no spec/contract change, no
backend touch. **Runs fully parallel** with the Wave-1 lane (#86) — no regen hold.

## Guest-gate behaviour

Favorites are **deliberately guest-local** (documented NOT-ACTIONABLE in
`favorites-probable-resolution.md`: *"guest-local favorites (deliberate — no auth
wall)"*). FAV-07 **preserves** that — the snapshot is device-local, so the price-drop
cue works identically for guest and authed users with **no new auth wall** and no
broken state. (The lane prompt's generic "favorites = auth-gated" boilerplate does not
match this surface's intended design; the operative requirement — *graceful, never a
broken state for guests* — is met.)

## Read-path-real (the #176 lesson)

- The **live** price is the real backend value: the favorites grid already resolves
  products via `POST /products/batch` → `ProductSummary.priceMinor`.
- The **snapshot** is the genuine price the user saw at favorite-time (captured from
  the same `ProductSummary` / PDP price they were looking at). Nothing fabricated.
- **Pre-existing favorites** (saved before this lane) have **no snapshot** → **no
  badge** (graceful fallback to the card's generic strikethrough). We do **not**
  back-fill a fake historical price (anti-goal #1).

## Plan (commit per concern)

1. **Scoping note** (this doc).
2. **Snapshot store** — `FavoritesNotifier` records the price at favorite-toggle in a
   `SharedPreferences` map (`mopro_favorite_prices`), keyed by product id; cleared on
   un-favorite. `toggle(productId, {priceMinor})` — backward-compatible optional arg;
   call sites that hold a price pass it (`ProductCard`, PDP, cart "move to favorites").
   `priceAtFavorite(id)` accessor.
3. **The cue** — `_FavCard` (the favorites-local wrapper, **not** the shared
   `ProductCard` — §3 dodge, same as FAV-05) shows a "Fiyatı düştü −%X" badge when
   `live < snapshot`. i18n `favorites.price_dropped` (TR + EN).
4. **Tests** — notifier snapshot capture/clear/round-trip; widget test that the badge
   shows on a drop and is absent without a snapshot.
5. Audit + `CUTOVER_LEDGER.md` update.

§5: no cross-schema reads (FE-only). §6: no PII (a price integer). No override-merge;
no deploy.
