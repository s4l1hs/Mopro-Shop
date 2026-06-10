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
  - **CONFIRMED (src), actionable: 4** — **FAV-02** one-way sync / no cross-device
    (MED–HIGH), **FAV-03** hardcoded "Temizle" (LOW), **FAV-04** error → infinite
    skeleton (LOW), **FAV-01** flat list / no collections (MED, = main-audit P-013).
  - **PROBABLE (await walk): 3** — **FAV-05** no add-to-cart on the card (LOW–MED),
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
| **FAV-02** | **One-way sync only.** `POST /favorites/sync` upserts local→server on login; there is **no `GET /favorites`** / server→local hydration. The mobile list reads SharedPreferences only; `user_favorites` server rows feed **just the aggregate favorites-count** (P-004), never the user's own list. → **a new-device login shows empty favorites; favorites don't sync across devices**, and a cleared app loses them. | src | **CONFIRMED** | **MED–HIGH** |
| **FAV-03** | The app-bar **clear-all button label is a hardcoded `'Temizle'`** (favorites_screen.dart) — not `.tr()`, breaks non-TR locales + the no-hardcoded-strings rule. (Everything else on the screen is i18n'd.) | src | **CONFIRMED** | LOW |
| **FAV-04** | **Error state → infinite skeleton.** Both `error:` and a successfully-fetched-but-empty `data:` fall back to `_SkeletonGrid()`, so a `/products/batch` failure renders as **perpetual loading** with no error/retry affordance. | src | **CONFIRMED** | LOW |
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

## §8 — Fix queue (when actioned — small, given card inheritance)

1. **FAV-03** (trivial) — i18n the "Temizle" label (`favorites.clear_all`).
2. **FAV-04** (trivial) — a real error state (message + retry) instead of the
   infinite skeleton; distinguish error from empty-data.
3. **FAV-02** (substantive) — add `GET /favorites` + hydrate the local set from the
   server on login (two-way sync) for cross-device favorites. Backend + mobile.
4. **FAV-05 / FAV-06 / FAV-07 / FAV-01** — await the walk to confirm the Trendyol
   side before sizing (add-to-cart on card; sort/filter; price-drop-since-favorited;
   collections/lists). FAV-01 = the flagship audit's P-013.

> **Status: SEEDED — awaiting Salih's walk.** Trendyol-side confidences (PROBABLE)
> firm up once Salih audits his own logged-in favorites.
