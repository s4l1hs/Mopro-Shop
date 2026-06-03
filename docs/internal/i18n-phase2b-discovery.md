# P-014 Phase 2b discovery — account area (security_screen + account_screen)

Branch `feat/i18n-sweep-2b-account` off `main@6f703700` (incl. #80). **Full-file reads** (not diacritic grep — #80 lesson). Both files done in one PR (the real diff is ~500 LOC — full rewrites preserve code, only strings change — well under the §9 ceiling), so **no per-file split**; Phase 2b closes whole.

## security_screen.dart — ~35 strings (the complex file)

Categories: 2 `const _SectionLabel`s, 2 `_RowCard` title/subtitle pairs (MFA active/inactive variants), 2 `const`-Text snackbars + 1 `const`-Text confirm dialog (4 inner Texts), the change-password sheet (labels/hints/validators/submit/3 error strings), the MFA-enroll sheet (prompts/labels/submit/4 error strings + **2 interpolated** errors). Namespace: **top-level `security.*`** — `account.security` already exists as a string key ("Güvenlik"), so a nested `account.security.*` object would collide.
- **const handling:** `const _SectionLabel('…')` → drop const; `const SnackBar(content: Text('…'))` → drop const; the disable-MFA `AlertDialog`'s inner `const Text`s → drop const (dialog itself already non-const).
- **Interpolated (namedArgs, literal key):** `'Hata: ${e.message ?? "bilinmeyen"}'` → `security.error_generic` = "Hata: {msg}" + `security.unknown` = "bilinmeyen"; `'Kod gönderilemedi: ${statusCode ?? "bağlantı hatası"}'` → `security.code_send_failed` = "Kod gönderilemedi: {status}" + `security.connection_error` = "bağlantı hatası".
- **Reuse:** `auth.sign_up.required` ("Zorunlu"), `auth.sign_up.password_hint` ("En az 8 karakter"), `auth.sign_up.password_mismatch` ("Parolalar eşleşmiyor"). "Parolamı Değiştir" + "MFA'yı Etkinleştir" each used twice → one key each.
- **Inline-kept (not language):** `'••••••••'`, `'+905551234567'`, `'000000'` (masks/placeholders).

## account_screen.dart — ~20 new strings (simpler: no interpolation/dialogs)

Categories: section headers ("Hesap Ayarları", "Görünüm"), stat labels ("Aktif Sipariş", "Mopro Coin", "Aktif Plan"), greeting ("Merhaba! 👋", "Hesabım"), theme labels (`_ThemeTile` + `_GuestMenu` share — dedup), guest header ("Hoş geldin!", "Tüm fırsatlardan…"), softGated prompts (3), guest menu rows. Namespace: **`account.*`** (existing group; add new keys — checked, no conflicts).
- **const handling:** `const Expanded(child: Column(children:[Text,Text]))` in both headers → drop const; `const Text('Giriş Yap'/'Üye Ol')` buttons → drop const.
- **Reuse:** `account.title` ("Hesabım"), `account.orders`/`my_orders` ("Siparişlerim"), `account.wallet` ("Cüzdanım"), `account.addresses` ("Adreslerim"), `account.menu_help` ("Yardım"), `account.menu_register` ("Üye Ol"), `auth.login` ("Giriş Yap"), `account.theme_light`/`theme_dark` (semantic labels, already used). Theme titles ("Açık Tema"/"Koyu Tema"/"Sistem Teması") are *distinct* from existing `account.theme_light`="Açık" (different copy) → new `account.theme_*_title`.
- **softGated prompts** are the auth-gate copy (VERIFIED-COMPLETE in #77 §4.4) — i18n-route only, preserve meaning. New `account.softgate_*`.

## Goldens (corrected expectation)

- `account_security_*` (security_screen) → **WILL change** Turkish→keys (harness renders keys — #79). Regen via `golden-rebaseline`.
- `account_welcome_*` / `account_profile_*` render the **wide-pane** widgets (`AccountWelcomePanel`, `profile_screen`), **not** `account_screen.dart`'s mobile body → unchanged here.
- The account *mobile* body (`_AccountMobileBody`/`_GuestMenu`) isn't golden-captured.

## Breaking tests (handle per #79 pattern: key + JSON)

`theme_picker_test` (theme labels), `flow_u_account_two_pane`, `help_widgets_test:37 find.text('Hesabım')`, `screen_audit_support` may assert swept strings → verify + fix (assert key, or verify key→TR from JSON). `account_goldens_test` = golden regen (account_security), not assertion.

## Plan

commit 1 discovery · commit 2 security_screen + `security.*` keys · commit 3 account_screen + `account.*` keys · commit 4 test fixes (#79 pattern) · commit 5 goldens (CI) · commit 6 closure. Keys co-located with each file's sweep (each commit gate-consistent). Gates after each. 0 TRANSLATION_NEEDED target. **No `'key'.tr()` literals in comments** (recurring #79/#80 false-positive).
