# P-014 discovery — i18n hardcoded-string sweep + `t()` helper refactor

Closes the P-014 split from PR #78. Branch `feat/i18n-hardcoded-sweep` off `main@36363410`.

## The `t()` helper (re-verified)

`mobile/lib/core/router/app_router.dart:86` — `String t(String s) => 'Mopro · $s';` — a **brand-title
prefixer, not a localiser**, despite the name. It is a *local* function inside `_titleForLocation`
(used only there — `git grep` confirms no external call sites). PR #78's claim is accurate.

**46 call sites**, all inside `_titleForLocation`, in three shapes:
- ~38 static literals: `t('Hesabım')`, `t('Giriş')`, … (page/tab titles for the `Title` widget).
- 4 interpolated: `t('İade #$name')`, `t('Sipariş #$name')`, `t('"$name" araması')`, `t('Arama: "$name"')`.
- 2 pass-throughs: `t(name)` (seller store name, help article name — runtime content, not a key).

## Decision: rename `t` → `withBrand`, route the argument through `.tr()` (Option A, with C's clarity)

Rename for honesty (`_withBrand(String) => 'Mopro · $s'`) and pass an **already-translated** string:
`_withBrand('router_title.account'.tr())`. **Why not Option B** (`t(key)` does `.tr()` internally):
the Step-3 usage analyzer (`check_i18n_usage.dart`) detects key usage only via a literal `'key'.tr(`
pattern (`_directTr`/`_interpTr` regexes) and **flags a non-literal receiver as unresolved**. Option B
hides `.tr()` inside the helper → the keys would read as *dead* (declared, never `.tr()`-used) and the
ratchet would fail. Option A keeps `.tr()` explicit at the call site → analyzer-clean. The brand prefix
`'Mopro · '` stays verbatim (brand constant — left inline by design).
- Interpolated → `_withBrand('router_title.return_numbered'.tr(namedArgs: {'n': name}))` (literal key + `.tr(` ⇒ analyzer-detected).
- Pass-through → `_withBrand(name)` (runtime content; no key, no `.tr()` — correct).

## Keys: dedicated `router_title.*` group (not reuse)

App-router titles get a **dedicated `router_title.*` group** with the **verbatim** current TR strings,
rather than reusing `nav.*`/`account.*`/etc. Rationale: (a) §8 verbatim preservation — page titles
must not silently change, and existing nav-label/header values may differ subtly (e.g. nav "Sepet" vs
title "Sepetim"); (b) page titles legitimately decouple from nav labels. ~44 keys (40 static + 4 namedArgs).
Gate-safe: extra keys in the master are fine; `i18n-check` only fails on keys *absent* from the tr-TR master.

## `Text()` literal + `auth_layout` + search sweep (the scattered set)

Re-verified `Text('…TR…')` literals (the 11 from #78, current line numbers): `account/security_screen.dart`
(5: 3 SnackBars + "Vazgeç" + "Telefon numarasını değiştir"), `auth/email_verify_screen.dart` (2),
`catalog/screens/product_detail_screen.dart:57` ("Ürün bulunamadı."), `checkout/presentation/checkout_redirect_screen.dart`
(2 buttons), `favorites/favorites_screen.dart:174` ("Keşfet"). Plus:
- `core/layout/auth_layout.dart`: headline (`const Text('Alışveriş yap,\ngeri kazan.')`) + a **`static const _valueProps`** list of `(IconData, String)` (3 marketing strings). The const list must become a **build-time list with literal `'key'.tr()`** per item (a `item.$2.tr()` dynamic receiver would be flagged unresolved by the analyzer).
- `catalog/screens/search_screen.dart:43`: `ApplicationSwitcherDescription` label `'Mopro · Arama'` / `'Mopro · "$query" araması'` — **reuses** `router_title.search` / `router_title.search_query` with `'Mopro · '` kept inline (brand).

**Reuse mostly blocked by §8 verbatim:** `common.cancel`="İptal" ≠ "Vazgeç"; `empty_state.not_found_message`="Aradığınız ürün bulunamadı." ≠ "Ürün bulunamadı." → new keys (`common.dismiss`, `product.not_found`). New scattered keys (~14): `security.{mfa_enabled,mfa_disabled,password_updated,change_phone}`, `common.dismiss`, `auth.verify_email.{code_resent,resend_code}`, `auth.layout.{headline,value_prop_shipping,value_prop_cashback,value_prop_secure}`, `checkout.{go_to_orders,continue_shopping}`, `product.not_found`, `favorites.explore`.

## const-correctness

Several literals are inside `const` widgets (e.g. `const SnackBar(content: Text('…'))`, `const Text('…')`).
`.tr()` is not const → drop `const` at those sites (keep inner `const TextStyle`). `flutter analyze` gates this.

## Gates + goldens

- **i18n-check** (`--strict`): tr-TR is master; new keys added to tr-TR + en-US; de-DE/ar-AE stay partial (missing = informational). Pass.
- **i18n-usage** (ratchet): every new key is declared (tr-TR) **and** used via literal `'key'.tr(` → not dead, not missing. No new unresolved receivers. Baseline unchanged.
- **Goldens:** the test harness renders **`Locale('tr','TR')`** (supported+fallback). TR values are preserved **verbatim** ⇒ rendered text is byte-identical ⇒ **no golden change expected**. App-router titles use the non-painted `Title` widget anyway. CI's `flutter test` (golden job) is the arbiter; rebaseline only if it reports a diff.

## Commit plan (each commit gate-consistent — keys co-located with their usage)

1. discovery (this doc) · 2. rename `t`→`_withBrand` (args unchanged literals — behaviour identical) ·
3. app_router titles → `.tr()` + `router_title.*` keys (tr+en) · 4. Text()/auth_layout/search → `.tr()` + scattered keys (tr+en) ·
5. goldens (expected no-op; confirm via CI) · 6. closure (audit P-014 RESOLVED + REPORT + ROADMAP).

## Outcome

P-014 RESOLVED (full sweep). ~44 router_title + ~14 scattered keys; 46 app_router sites + ~16 scattered sites; `t()`→`_withBrand`. 0 TRANSLATION_NEEDED expected (all TR known; EN standard UI terms).
