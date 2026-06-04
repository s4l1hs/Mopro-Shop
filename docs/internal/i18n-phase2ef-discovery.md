# P-014 Phase 2e + 2f discovery — checkout + singletons (closes P-014)

Branch `feat/i18n-sweep-2ef` off `main@d5ab86e5` (incl. #82). **Aspirational 0-split outcome reachable:** cart + checkout were built with `.tr()` from Phase 4.5, so the *remaining* P-014 strings are small (~32 across ~14 files) — far below the prompt's 80–150 estimate. **This PR closes P-014 entirely** (2e checkout + 2f singletons + the last home/catalog stragglers).

## Remaining inventory (full reads; diacritic grep undercounted ~30%)

**2e checkout (cart/checkout were already mostly localized):**
- `checkout/presentation/checkout_redirect_screen.dart` — **8** (not 6): `const _loadingMessages` list of 4 (incl. ASCII-only 'Bankadan onay bekleniyor…'), timeout title 'Onay biraz gecikiyor' (ASCII-only — grep missed), timeout body, 2 buttons. → `checkout.redirect.*`; const list → build-time localized list (a `_loadingMessages[i].tr()` would be unresolved); keep a `const _loadingMessageCount = 4` for the cycle modulo.
- `cart/presentation/cart_screen.dart` — **1**: softGated reason → `cart.checkout_login_reason`.

**2f singletons:**
- `shell/web_header.dart` (1, 'Giriş Yap') → **reuse `auth.login`** (updates `web_header_test`'s `find.text('Giriş Yap')`).
- `shell/header_search_bar.dart` (1) → `search.web_placeholder`.
- `widgets/theme_toggle.dart` (2, dark/light tooltip) → new `theme.toggle_dark`/`toggle_light`.
- `features/web/mega_menu/mega_menu_panel.dart` (1, interpolated) → `mega_menu.see_all` (namedArgs `{category}`).
- `features/web/mega_menu/mega_menu_bar.dart` (1, a11y hint) → `mega_menu.submenu_hint`.
- `features/favorites/favorites_screen.dart` (1, 'Keşfet') → `favorites.explore`.
- `features/catalog/screens/product_detail_screen.dart` (1, 'Ürün bulunamadı.') → `product.not_found`.
- `features/catalog/screens/search_screen.dart` (2, app-switcher label) → **reuse `router_title.search`/`search_query`** with `'Mopro · '` inline (brand).
- `features/help/help_article_screen.dart` (1, interpolated tab title) → `help.article_title` (namedArgs `{title}`).
- `core/router/app_router.dart` (1, `_titled('Hesabım', …)`) → **reuse `account.title`**.

**home/catalog stragglers (the last bits to fully close P-014):**
- `catalog/screens/home_screen.dart` — 4 `_defaultHints` (search-pill placeholders) → `home.search_hint_*`. const list → build-time.
- `catalog/providers/home_provider.dart` — 3 rail-fallback titles → `home.rail.recommended`/`bestseller`/`newest`; 4 trending-search fallbacks → `home.trending.*`. **Both are fallback data** (backend normally provides localized via `/home/rails`,`/search/trending`); localized for completeness — EN values are search-term equivalents. const→build-time in the `catch` blocks (global `.tr()` works in providers).

**VERIFIED-COMPLETE:** `account/widgets/account_left_rail.dart` `'tr': 'Türkçe'` — a language self-name in the locale map (correctly inline, like profile_screen in 2d).

## ~32 keys; reuses

Reuse: `auth.login` (web_header), `account.title` (app_router), `router_title.search`/`search_query` (search_screen app-switcher). New namespaces: `checkout.redirect.*`, `cart.checkout_login_reason`, `search.web_placeholder`, `theme.*`, `mega_menu.{see_all,submenu_hint}`, `favorites.explore`, `product.not_found`, `help.article_title`, `home.{search_hint_*,rail.*,trending.*}`. 0 TRANSLATION_NEEDED (no legal-text in the remainder — the checkout consent/T&C strings were already localized in earlier phases).

## Goldens (predict per #81/#82)

- web_header golden(s) (`shell/goldens/web_header_*`) — render 'Giriş Yap' (guest state) → **flip to key** `auth.login`. Predict regen.
- home goldens (`home_*`) — render the search pill (`_defaultHints`) → if the pill text is captured, **flip**. Predict possible regen. (mood-stories/rails come from providers stubbed in the golden test; the `_defaultHints` are local → likely captured.)
- search_screen / product_detail / favorites / mega_menu / checkout_redirect — verify; auth/checkout screens historically not golden-captured (#80/#82).
- **Predict, then verify via rebaseline; investigate any unpredicted diff or missing-predicted (orphan).**

## Plan

commit 1 discovery · 2 checkout (redirect+cart) · 3 singletons (web_header/header_search/theme_toggle/mega_menu/favorites/product_detail/search/help/app_router) · 4 home stragglers · 5 keys-are-co-located-per-commit · 6 web_header_test + any breaks · 7 goldens (CI) · 8 closure (**P-014 CLOSED**). Each commit gate-consistent. No `'key'.tr()` in comments.
