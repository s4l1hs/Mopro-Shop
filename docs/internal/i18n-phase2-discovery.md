# P-014 Phase 2a+2b+2c discovery — auth + account + sipay error map

Branch `feat/i18n-sweep-2abc` off `main@b1bab9de` (incl. #79). Closes 6 of the 27 P-014 files / 94 of ~111 strings.

## Counts (re-verified, all sinks)

| Phase | File | strings |
|---|---|---|
| 2a auth | `features/auth/sign_up_screen.dart` | 15 |
| 2a | `features/auth/sign_in_screen.dart` | 12 |
| 2a | `core/layout/auth_layout.dart` | 4 |
| 2b account | `features/account/security_screen.dart` | 29 |
| 2b | `features/account/account_screen.dart` | 21 |
| 2c payment | `features/payments/sipay_error_map.dart` | 13 (12 map + 1 fallback) |

Sinks vary: `Text()`, `hint:`/`label:`/`header:` params, `FormField` validators (return strings), error `switch` arms, `SnackBar` content (`const`), dialog content, interpolated (`'… ${e.statusCode}'`).

## ⚠️ Discovery-shift: goldens WILL change (prompt's "0 regen" is wrong)

The repo's golden/widget test harness does **not** load the translation bundle — `.tr()` returns the **key** (proven in #79: Linux CI `flutter test` logged "router_title.X not found"; `account_goldens_test` uses the same `EasyLocalization`+`ensureInitialized` setup). So screens that are **currently hardcoded Turkish** render Turkish in their goldens today; converting them to `.tr()` makes them render the **key** → the goldens change (Turkish → keys). Affected: `account_security_*`, `account_welcome_*` (account_screen), `auth_card_dialog_*` / login-flow goldens (auth). **Must regen via the `golden-rebaseline` workflow.** This is consistent with the rest of the app (existing `.tr()` content already renders as keys in goldens).
**New finding (filed, not fixed here):** the golden harness should load translations so goldens are visually faithful (a one-time infra fix + full rebaseline — out of this PR's scope; §8).

**No test-assertion breaks:** `git grep find.text('…TR…')` over the 6 screens → none (unlike #79's page_title_test). So no test rewrites needed; only golden regen.

## Reuse vs new keys (§8 verbatim)

Reuse **exact-verbatim** existing keys; create new otherwise. Confirmed reuses:
- `auth.network_error` ("Bağlantı hatası. İnternet bağlantınızı kontrol edin.") → sign_up/sign_in network error.
- `auth.unknown_error` ("Bir hata oluştu. Lütfen tekrar deneyin.") → sign_up/sign_in `_ =>` arm.
- `auth.login` ("Giriş Yap") → sign_in title + submit.
- `account.title` ("Hesabım"), `account.orders` ("Siparişlerim"), `account.menu_help` ("Yardım") → account_screen.
- `account.menu_login_prompt` ("Hesabınıza giriş yapın") → sign_in subtitle.
New namespaces: `auth.sign_up.*`, `auth.sign_in.*`, `auth.layout.*`, `account.security.*`, `account.settings.*`, `payment.error.sipay.*`. Verbatim differences block reuse (e.g. sign_in rate-limit "…biraz bekleyin." ≠ `auth.rate_limit` "…1 dakika sonra…"; "Giriş yap" link ≠ "Giriş Yap").

## Phase 2c — sipay error map (dynamic key, no goldens)

`sipay_error_map.dart` is a `static const Map<String,String>` (12 codes) + `_fallback`. Rewrite to map code→message via **`'payment.error.sipay.$known'.tr()`** where `known` is validated against a const `Set` of codes (unknown → `unknown`). Interpolated-literal `.tr(` → the usage analyzer auto-derives the `payment.error.sipay.` prefix → keys covered (not dead/missing). 12 keys; EN must stay **actionable** (§4.3.3), e.g. `insufficient_funds` → "Your card has insufficient balance. Please try another card." 0 TRANSLATION_NEEDED.

## const-correctness

`const SnackBar(content: Text('…'))`, `const Text('…')`, `const _SectionLabel('…')`, the auth_layout `static const _valueProps` list → drop `const` at the `.tr()` site (keep inner `const TextStyle`); auth_layout list → build-time list with literal `'key'.tr()` per item (per #79; a `item.$2.tr()` dynamic receiver would be flagged unresolved). `flutter analyze` gates this.

## Plan

Per-phase commit, **keys co-located with each phase's usage** (so each commit is gate-consistent — cleaner than a separate keys commit). Gates after each: `i18n-check` (extras), `i18n-usage` (dead/missing), `flutter analyze`. Goldens regen via CI after push. Split 2b (account) if it balloons (§6/§9 — highest variance). 0 TRANSLATION_NEEDED target.

## ⚠️ Second discovery-shift: diacritic grep undercounts ~2× → 2b split

Reading `sign_up_screen` in full showed **~24** user-facing strings, not the 15 the grep reported: the diacritic-based grep (`[ğşıİçöüĞŞÇÖÜ]`) **misses Turkish strings without special chars** — "Ad", "Soyad", "Parola", "E-posta", "Zorunlu", "Kayıt Ol", "Hesap Oluştur", "Giriş", etc. So **every per-file count (and the ~155 total) is undercounted, roughly 2×** — true P-014 scope is likely ~250–300 strings. (Counting fix for future phases: read the file, or grep UI sinks `Text(`/`label:`/`hint:`/`header:`/`validator`/switch-arms, not just diacritics.)

## Outcome (what shipped)

- **Phase 2c (sipay) ✅** — `sipay_error_map.dart` → `'payment.error.sipay.$code'.tr()` (dynamic prefix); 12 keys; test rewritten (#79 pattern). No goldens.
- **Phase 2a (auth) ✅** — sign_up + sign_in + auth_layout, **~46 strings** (true count), reuse + new `auth.*`/`auth.sign_up.*`/`auth.sign_in.*`/`auth.layout.*`; `_valueProps` const→build-time. auth goldens (auth_card / login flow) regen via CI.
- **Phase 2b (account) ⤿ SPLIT** → `feat/i18n-sweep-2b-account`. With the ~2× undercount, `security_screen` (≈40, incl. interpolated `'Kod gönderilemedi: ${…}'`, const dialogs/snackbars, the phone-change flow) + `account_screen` (≈30, theme-label dedup, softGated prompts) is the high-variance half (§9). Splitting keeps quality + review surface sane (§6 "ship 2 phases; 3rd carves out"). Its goldens (`account_security_*`, `account_welcome_*`) change Turkish→keys there, not here.

This PR closes **Phases 2a + 2c** (P-014 Phases 1/2a/2c done). Title reflects that, not 2b. Both i18n-gate false-positives from `'key'.tr()`-in-comments (auth_layout) were caught + rephrased (recurring #79 hazard).
