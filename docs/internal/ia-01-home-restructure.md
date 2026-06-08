# IA-01 — Home IA restructure: categories → Home + Coin tab (discovery)

> Two structural moves: (1) a category shortcut rail + "Tüm Kategoriler" entry on
> Home → the full tree; (2) the **Categories** bottom-nav tab becomes a **Coin**
> tab → a routed placeholder (IA-02 fills it). Deliberate divergence from
> Trendyol (Salih's direction). **Outcome A (clean)** — the tree decouples from
> the tab without rebuild; deep-links handled by keeping `/categories` resolvable.

## Current structure (authoritative sites)

- **Router** `mobile/lib/core/router/app_router.dart`:
  - `StatefulShellRoute.indexedStack` (L713) → `AppShell`, **5 branches**:
    `0 /` (home), `1 /categories` (**CategoryScreen** tree, key `_categoriesNavKey`),
    `2 /favorites`, `3 /cart`, `4 /account`. Branch screens carry their own
    `Scaffold`/`AppBar`; `_titled` only sets the window `Title`.
  - `/categories/:id` (L500) is a **top-level** route (category PLP), with an
    invalid-id redirect `context.go('/categories')` (L508).
  - Title rule `if (location == '/categories')` (L152).
- **Mobile nav** `mobile/lib/shell/app_shell.dart` `_MobileShell` — the real
  bottom bar: Home / **Categories** (`Icons.grid_view`, `nav.categories`, branch 1)
  / Favorites / Cart / Account. `_branch(i)` → `navigationShell.goBranch(i)`.
- **Web/desktop** `_WebShell` (≥768): `WebHeader` + `MegaMenuBar` for categories,
  **no bottom nav**; category nav uses top-level `/categories/:id` routes. The
  branch reindex doesn't affect it as long as `/categories` resolves.
- **Discovery shift — a 2nd, DEAD nav:** `mobile/lib/core/widgets/bottom_nav_shell.dart`
  (`BottomNavShell`: home/categories/cart/wallet/profile) is **referenced
  nowhere** (grep-confirmed). Not the rendered nav; left untouched (deleting it
  is out of scope / unbundled).

## Home + category data

- `home_screen.dart` `CatalogHomeScreen` slivers: mood-stories, banner, flash
  deals, **`HomeCategoryGrid`** (L92), trust bar, product rails, recs, recently-viewed.
- `HomeCategoryGrid` (`features/catalog/widgets/home_category_grid.dart`) is used
  **only** on Home (grep-confirmed). It renders root-category pucks in a *grid*
  (`take(perRow)`), each → `context.push('/categories/:id')` (PLP). **No "all
  categories" entry**, and it's a grid, not a horizontal rail.
- Category data: `categoriesProvider` (`features/catalog/providers/categories_provider.dart`)
  — roots = `parentId == null`. Reused by the rail.
- The tree screen `CategoryScreen` (`features/catalog/screens/category_screen.dart`)
  has its own `Scaffold` + `AppBar('catalog.categories')` → works as a **pushed
  full screen** (auto back button).
- Home product rails already `seeAllRoute: '/categories'` via `context.push`
  (`product_rail.dart` L64) — so `/categories` MUST keep resolving.

## Deep-links / callers of `/categories` (tree)

`seeAllRoute` push (home rails), invalid-id redirect (L508 go), title rule (L152).
All keep working once `/categories` is a top-level route. `/categories/:id` (PLP)
is independent and unchanged. **Outcome A** — no redirect-to-Home needed; the
"redirect so deep-links don't 404" requirement is met by keeping `/categories`
resolvable (top-level), not by bouncing it.

## i18n

`nav` (tr-TR master) has home/categories/favorites/cart/account (+ unused
wallet/profile). Add `nav.coin`, `home.all_categories` ("Tüm Kategoriler"),
`coin.placeholder_*`. No existing `coin.*` keys. Add to tr-TR (master) + en-US;
gate fails on EXTRA keys / dead+missing — add only what's used.

## Plan (one commit per concern)

1. This doc.
2. **Home rail + entry:** new `HomeCategoryRail` (horizontal pucks via
   `categoriesProvider`, reusing the puck cell; trailing **"Tüm Kategoriler"**
   puck → `context.push('/categories')`). Swap `HomeCategoryGrid` → rail in
   `home_screen.dart`; delete the now-unused grid.
3. **Re-point tree:** remove the `/categories` shell branch; add `/categories`
   as a **top-level** `GoRoute` → `_titled('Kategoriler', CategoryScreen())`.
4. **Nav Categories → Coin:** branch 1 → `_coinNavKey` `/coin` → new
   `CoinScreen` placeholder (Scaffold+AppBar+centered copy; IA-02 fills it);
   `_MobileShell` nav item 1 → coin icon (`Icons.monetization_on_*`) + `nav.coin`.
   `/categories` deep-links resolve (top-level) → no 404.
5. **i18n:** `nav.coin`, `home.all_categories`, `coin.placeholder_title/body`
   (TR + EN). 0 dead / 0 missing.
6. **Goldens:** predicted flips — Home (category section grid→rail) + bottom nav
   (slot 1 icon+label Categories→Coin). Regen on **Linux** via
   `golden-rebaseline.yml` (never macOS); reconcile actual vs predicted.
   (No golden CI gate in `make verify`, so it stays green; regen is operational.)

## Verification + golden reconciliation (post-impl)

- **Emulator (local):** Coin tab → "Mopro Coin" placeholder ✅; horizontal
  category rail on Home ✅; a rail puck pushes the `/categories/:id` PLP route ✅
  (data fetch hit the known adb-reverse tunnel flake — routing resolved, not a
  regression). The `/categories` tree + "Tüm Kategoriler" entry use the same
  top-level `push` mechanism the puck exercised; CategoryScreen carries its own
  AppBar. `make verify` green; flutter analyze / i18n (0/0) / riverpod green.
- **Golden flips (predicted == confirmed-shape):** `home_goldens_5a` ×3
  (mobile/tablet/desktop — category grid→rail) + `app_shell bottom_nav`
  light/dark (slot-1 icon/label) = **5 files**. The `app_shell_test` *icon*
  assertions (non-golden) were updated in-tree (grid_view→monetization_on).
  NOTE: on macOS the platform-guarded comparator fails **all** Linux-baselined
  goldens (e.g. web_header, account_hover — untouched), so macOS runs can't
  enumerate flips; the 5 above are determined analytically (only Home's category
  section + the nav slot-1 changed; flash-deals/recs goldens render those
  widgets in isolation, unaffected). Regen on Linux + reconcile when the branch
  is pushed/PR'd.
- **F-021 fallout fixed here:** 3 consumer test fixtures
  (recently-viewed / recommendations) still emitted `monthly_amount_minor`;
  updated to `monthly_coin_minor` (these aren't in `make verify`, so F-021
  missed them).
