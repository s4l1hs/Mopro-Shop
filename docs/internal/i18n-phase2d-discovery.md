# P-014 Phase 2d discovery — email_verify + mfa + forgot + marketing/hero

Branch `feat/i18n-sweep-2d` off `main@b7efdd4a` (incl. #81). Full-file reads. **~34 new keys, single PR** (no split — the prompt's "3 MFA files" fear is wrong: MFA enroll/disable already shipped *inside* security_screen in 2b; only the login-time `mfa_challenge_screen` remains).

## Files + counts (full read)

| File | strings | notes |
|---|---|---|
| `features/auth/email_verify_screen.dart` | ~10 | RichText (email in middle) → prefix/suffix keys; const SnackBar/TextSpan/Text drops |
| `features/auth/mfa_challenge_screen.dart` | ~8 | RichText (masked phone) → prefix/suffix; shares code-entry keys with email_verify |
| `features/auth/forgot_password_screen.dart` | ~8 | reuses 2a `auth.email_label`/`email_hint`/`email_invalid` |
| `features/auth/auth_widgets.dart` | 5 | 4 PasswordStrengthIndicator rules + `'veya'` (AuthOrDivider) |
| `data/hero_slides.dart` | 8 | **`const heroSlides` list → function** `heroSlides()` with literal `.tr()` (consumer `hero_carousel.dart` updated; a `slide.title.tr()` dynamic receiver would be flagged unresolved) |
| `features/auth/profile_screen.dart` | 0 | **VERIFIED-COMPLETE** — already fully `.tr()`; the 1 diacritic hit is `'Türkçe'`/`'العربية'` = language self-names in the locale picker (correctly inline) |

## Key plan (namespaces)

- **Shared `auth.*`** (email_verify + mfa both use): `code_label`="Doğrulama Kodu", `verify_action`="Doğrula", `error_invalid_code`="Hatalı kod. Lütfen tekrar deneyin.", `error_generic_short`="Bir hata oluştu." (distinct from existing `auth.unknown_error`="…Lütfen tekrar deneyin.").
- **`auth.email_verify.*`**: resent_toast, title, code_sent_prefix/suffix (RichText), resend, error_expired.
- **`auth.mfa.*`**: title ("İki Faktörlü Doğrulama" — distinct from `security.section_mfa` which has "(MFA)"), code_sent_prefix/suffix, error_expired, error_rate_limited ("…Lütfen bekleyin." — distinct from `auth.sign_in.error_rate_limited`/`auth.rate_limit`).
- **`auth.forgot.*`**: title ("Şifremi Unuttum" — distinct from `router_title.forgot_password`="Şifre Sıfırlama"), subtitle, send_link, sent_title, sent_body, back_to_login. Reuse `auth.email_label`/`email_hint`/`email_invalid`.
- **`auth.password_rule.*`**: min_length/upper/lower/special. **`auth.or`**="veya".
- **`marketing.hero.*`**: cashback_title/sub, secure_title/sub, shipping_title/sub, season_title/sub.

Inline-kept (not language): code placeholders `A3B7C2D8`/`000000`, `ornek@email.com` (reused 2a key anyway).

## Golden predictions (per #81)

- **home_* goldens flip** — `hero_carousel` (top of home_screen) renders `heroSlides()`; titles/subtitles → keys in the test harness. Predict `home_mobile_375`, `home_tablet_768`, `home_desktop_1440`.
- **auth screens (email_verify/mfa/forgot) likely 0 golden change** — like sign_in/sign_up in #80, not golden-captured (auth_card_dialog renders the login-required child, not these full screens). `auth_widgets` (strength indicator shows only while typing; AuthOrDivider on sign_in) — predict 0, but `auth_card_dialog` *might* show `'veya'` → verify.
- Confirm via the rebaseline run; investigate any unpredicted diff.

## Plan

commit 1 discovery · commit 2 email_verify + mfa_challenge (+ shared/email_verify/mfa keys) · commit 3 forgot_password + auth_widgets (+ forgot/password_rule/or keys) · commit 4 hero_slides + hero_carousel (+ marketing.hero keys) · commit 5 test fixes (#79 pattern) · commit 6 goldens (CI) · commit 7 closure. Keys co-located per commit (gate-consistent). 0 TRANSLATION_NEEDED target. No `'key'.tr()` in comments.
