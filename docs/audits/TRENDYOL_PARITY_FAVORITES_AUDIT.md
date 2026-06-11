# Trendyol Parity Audit — Favorites (Beğendiklerim)

> **Audit only — no code.** Self-audit of the Favorites surface against a
> **provisional** Trendyol baseline (§2), seeded for Salih's walk. IDs **FAV-NN**,
> #09 walk format. Sibling of the PLP / PDP / Search / Cart audits. `src` = Mopro
> code fact; `walk` = Salih's visual/interaction observation; `markup` = Trendyol
> SSR (favorites is auth-gated → **not** SSR-fetchable, so the Trendyol side is
> PROBABLE pending Salih's walk on his own account).
>
> **The grid reuses the already-parity'd `ProductCard`**, so most of the visual
> surface inherits (§4) — this audit focuses the **favorites-specific** behaviour.
>
> **Surface (source):** `mobile/lib/features/favorites/favorites_screen.dart`
> (`FavoritesScreen` + `_favProductsProvider` batch-fetch + `_EmptyState` +
> `_SkeletonGrid`) · `favorites_provider.dart` (`FavoritesNotifier`, a
> SharedPreferences `Set<int>`) · the card (`ProductCard`) · `POST /favorites/sync`
> (`cmd/core-svc` `handleFavoritesSync`) · `catalog_schema.user_favorites`.

---

## §0 — Legend

- **Source** — `src` (Mopro code fact) · `walk` (Salih, visual/interaction) ·
  `markup` (Trendyol SSR — **N/A here**, favorites is behind auth).
- **Confidence** — **CONFIRMED** (Mopro-side code fact) · **PROBABLE** (the
  *Trendyol* comparison awaits Salih's walk) · **RESOLVED** · **NOT-ACTIONABLE**
  (intentional divergence / Mopro PLUS).
- Card-inherited rows are tagged **[CARD]** and are **not** re-audited here (see the
  PLP/PDP audits for the card itself) — only that the favorites grid carries them.

---

## §1 — Summary

- **Architecture:** favorites are a **device-local** `Set<int>` of product IDs
  (SharedPreferences `mopro_favorites`); the grid hydrates them via
  `POST /products/batch`. On login the local set is pushed up via
  `POST /favorites/sync` (one-way upsert into `catalog_schema.user_favorites`).
- **Card inheritance CARRIES (§4):** the grid renders `ProductCard`, so image,
  brand, title, price, discount %/strikethrough + lowest-30d, cashback chip,
  free-shipping + bestseller + **official-seller** (PLP-17) badges, favorites-count
  overlay, and the heart toggle all inherit. No favorites-specific card gaps.
- **Favorites-specific findings: 7** —
  - **✅ RESOLVED (`feat/favorites-downsync`): 3** — **FAV-02** server→local
    down-sync (cross-device; `GET /favorites` + hydration), **FAV-03** i18n
    clear-all, **FAV-04** error-retry state.
  - **CONFIRMED (src), still open: 1** — **FAV-01** flat list / no collections
    (MED, = main-audit **P-013**, a separate flagship feature).
  - **PROBABLE → resolved source-side** (`feat/favorites-probable-resolution`, no walk; `docs/internal/favorites-probable-resolution.md`): **FAV-05** add-to-cart → **DEFER** (discovery shift: favorites store only product IDs, so ATC needs variant resolution — a quick-add sheet/PDP redirect — + touches the shared `ProductCard`, §3; not a clean button). **FAV-06** sort/filter → **NEEDS-DECISION** (UI feature, LOW). **FAV-07** price-drop-since-favorited → **DEFER** (needs a price-at-favorite snapshot; favorites hold only IDs). **0 CONFIRMED UI-only fixes.**
  - ~~**PROBABLE (await walk): 3**~~ (original) — **FAV-05** no add-to-cart on the card (LOW–MED),
    **FAV-06** no sort/filter (LOW), **FAV-07** no "fiyatı düştü since favorited"
    indicator (LOW–MED).
- **NOT-ACTIONABLE: 2** — guest-local favorites (no login wall — a deliberate
  Mopro choice, arguably *better* than Trendyol's auth-gate); coin/cashback chip.
- **Fix queue (§8):** FAV-03 + FAV-04 are trivial; FAV-02 is the substantive one.

---

## §2 — Canonical ID map (reconcile with the main audit — nothing lost)

The flagship `TRENDYOL_PARITY_AUDIT.md` already carries two favorites findings;
this doc is the **dedicated registry** and keeps them aligned (one meaning per ID):

| This doc | Finding | Main-audit alias |
|---|---|---|
| **FAV-01** | flat favorites list (no collections/folders) | **P-013** (favorites flat list) |
| **FAV-03** | hardcoded "Temizle" clear-all string | subset of **P-014** (hardcoded strings) |
| **[CARD] favorites-count** | count by the heart | **P-004** (RESOLVED backend-side) |

FAV-02/04/05/06/07 are **new** (favorites-specific, not in the flagship audit).

---

## §3 — Findings registry (favorites-specific)

| ID | Finding (Mopro current → Trendyol) | Source | Confidence | Sev |
|---|---|---|---|---|
| **FAV-01** | Favorites is a **flat set** — no collections/named lists/folders ("Listelerim"). Trendyol lets users organize favorites into lists. | src | **CONFIRMED** (Mopro); Trendyol PROBABLE | MED |
| **FAV-02** | ~~One-way sync only~~ → **✅ RESOLVED** (`feat/favorites-downsync`): added **`GET /favorites`** (requireAuth → `{product_ids}`, §5-safe single-schema query via a `favoritesReader` seam) + mobile **server→local hydration** (`hydrateFavoritesFromServer` → `FavoritesNotifier.mergeServer` union), triggered after the up-sync on login **and** fire-and-forget on launch when authed. Favorites are now **cross-device**. | src | **RESOLVED** | **MED–HIGH** |
| **FAV-03** | ~~hardcoded `'Temizle'` clear-all~~ → **✅ RESOLVED**: `favorites.clear_all`.tr() (en/tr). | src | **RESOLVED** | LOW |
| **FAV-04** | ~~error → infinite skeleton~~ → **✅ RESOLVED**: a `/products/batch` failure now renders `_ErrorState` (icon + message + **retry**), distinct from the empty/loading states. | src | **RESOLVED** | LOW |
| **FAV-05** | **No add-to-cart from the favorites card** — the card offers heart (remove) + tap→PDP only; no "Sepete Ekle". Trendyol's favorites cards have a direct add-to-cart. | src | **PROBABLE** (Trendyol) | LOW–MED |
| **FAV-06** | **No sort/filter** of favorites (insertion-order `Set`). Trendyol favorites can sort (price/discount) + filter. | src | **PROBABLE** | LOW |
| **FAV-07** | **No favorites-specific price-drop indicator** ("fiyatı düştü" since you favorited). Favorites store only IDs — no price-at-favorite snapshot — so the only price signal is the card's generic lowest-30d strikethrough, not a "dropped since you saved it" cue. | src | **PROBABLE** | LOW–MED |

---

## §4 — Card inheritance check (CARRIES — do **not** re-audit the card)

`FavoritesScreen` builds `ProductCard(product: p, isBestseller, isOfficialSeller,
basketDiscountPct, onTap→PDP)` — the **same** card the parity'd PLP/PDP grids use.
So the favorites grid inherits, with no favorites-only divergence:

| Card element | Inherited? | Notes |
|---|---|---|
| Square cover image + skeleton | ✅ | `SkeletonProductCard` while batch-fetching |
| Brand line / title / price | ✅ | identical mapping |
| Discount % + strikethrough + lowest-30d (P-030) | ✅ [CARD] | |
| Cashback chip (Mopro PLUS) | ✅ [CARD] | NOT-ACTIONABLE (intentional) |
| Free-shipping + **bestseller** + **official-seller (PLP-17)** badges | ✅ [CARD] | the just-shipped Resmi Satıcı badge carries here too |
| Favorites-count overlay (P-004) | ✅ [CARD] | |
| **Heart toggle = remove-from-favorites** | ✅ | the card's `_HeartButton` → `favoritesProvider.toggle`; works on the grid |
| Responsive columns (2 / 4 / 5) + centered tablet/desktop | ✅ | favorites-screen-local, matches the PLP grid conventions |

**Verdict: card-inheritance CARRIES (yes).** No card re-audit needed; the
favorites grid is visually at parity wherever the card is.

---

## §5 — Intentional divergences (NOT-ACTIONABLE — do not flag)

- **D1 — guest-local favorites (no login wall).** Mopro lets *guests* favorite
  (local `Set`) and merges up on login; Trendyol gates favorites behind auth. The
  guest-friendly behaviour is a **deliberate Mopro choice** (better first-run UX) —
  NOT a gap. *(The missing server→local **down**-sync is a separate, real gap —
  FAV-02 — not covered by this divergence.)*
- **D2 — coin/cashback chip on the card** (Mopro PLUS, business model).

---

## §6 — Walk slots (Salih, on a logged-in + a guest session)

1. **Grid + card** — favorite ~6 products across categories; confirm the grid
   renders the full card (badges/price/strikethrough/official-seller) at 2/4/5 cols.
2. **Empty state** — clear all → icon + title + subtitle + "Explore" CTA → home.
3. **Remove** — heart on a grid card removes it live; "Temizle" clears all
   (note the hardcoded label, FAV-03).
4. **Cross-device (FAV-02)** — favorite as guest → login → (does anything sync
   down? expected: no). Then login on a *second* device → favorites expected
   **empty** (confirms the one-way-sync gap).
5. **Add-to-cart (FAV-05)** — confirm Trendyol's favorites card has "Sepete Ekle";
   Mopro's does not.
6. **Sort/filter (FAV-06) + price-drop (FAV-07)** — confirm Trendyol exposes these
   on its favorites; Mopro has neither.
7. **Collections (FAV-01)** — confirm Trendyol's named lists; Mopro is flat.

---

## §7 — Seed / gating adequacy

- **No seed needed.** Favorites are populated **client-side** (tap any product's
  heart) — the grid, empty state, skeleton, and remove flows are all exercisable
  locally with the existing product seed. `POST /products/batch` hydrates them.
- **Auth not required** to exercise the surface (guest-local). To exercise the
  sync-up (FAV-02), log in after favoriting; the down-sync gap is observed by a
  *second* device / fresh install.

---

## §8 — Fix queue

1. ~~**FAV-03** — i18n the "Temizle" label~~ **✅ DONE** (`favorites.clear_all`).
2. ~~**FAV-04** — real error/retry state~~ **✅ DONE** (`_ErrorState`).
3. ~~**FAV-02** — `GET /favorites` + server→local hydration (cross-device)~~
   **✅ DONE** (`feat/favorites-downsync`): `GET /favorites` + `hydrateFavoritesFromServer`
   (login + launch), §5-safe, contract-tested. *(Two-way sync now: up via
   `/favorites/sync`, down via `/favorites`.)*
4. **FAV-05 / FAV-06 / FAV-07 / FAV-01** — await the walk to confirm the Trendyol
   side before sizing (add-to-cart on card; sort/filter; price-drop-since-favorited;
   collections/lists). FAV-01 = the flagship audit's P-013.

> **Status:** the substantive gap (FAV-02 cross-device) + the two polish items are
> **shipped**; FAV-05/06/07 + FAV-01 (collections) remain **awaiting Salih's walk**.
