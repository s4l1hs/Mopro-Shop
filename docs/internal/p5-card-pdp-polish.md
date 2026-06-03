# P5-1 + P5-2 discovery — card/PDP polish + dark-mode contrast

First Step-5 build PR (from `TRENDYOL_PARITY_AUDIT.md`). Re-verifies P-005, P-006, P-014, P-020
on `feat/parity-card-pdp-polish` (off `main@6d00a446`, which includes the #77 audit) before any change.

## Path reconciliation (prompt used generic paths)

| Prompt path | Real path |
|---|---|
| `features/<product-card>/**` | `mobile/lib/features/catalog/widgets/product_card.dart` |
| `features/pdp/**` | `mobile/lib/features/catalog/screens/product_detail_screen.dart` + `…/widgets/pdp/*` |
| `shared/widgets/discount_pill*` | **did not exist** — the discount badge was inline in two places (card + PDP price block) |
| `core/theme/` (tokens) | `mobile/lib/design/tokens.dart` + `mobile/lib/design/theme.dart` |
| `assets/translations/*.json` | `mobile/assets/translations/{tr-TR,en-US,de-DE,ar-AE}.json` |

## P-005 — token-drift on ProductCard → RESOLVED (1 real fix; 2 intentional inlines kept)

Re-verified `product_card.dart`. Three hardcoded values; only **one** is genuine drift:

| Site | Value | Verdict | Action |
|---|---|---|---|
| `:170` price color | `MoproTokens.primaryLight` | **DRIFT** — sits on `cs.surface` (theme-dependent); in dark mode rendered the *light-mode* orange `#CA4E00` on `surfaceDark` (worse than the P-020 pair). | → `cs.primary` (theme-aware). |
| `:219` active heart | `MoproTokens.primaryLight` | **INTENTIONAL** — heart sits on a hardcoded `Colors.white` chip (`_HeartButton`, theme-independent); `#CA4E00` on white = 4.56:1. `cs.primary` would put the *lighter* dark-mode orange on white (lower contrast). | keep + documented. |
| `:220` inactive heart | `Color(0xFF888888)` | **INTENTIONAL** — neutral grey outline on the white chip; no equivalent token (mutedFg is a warm brown). | keep + documented. |

So P-005 = swap the price to `cs.primary`. Light mode: no change (`cs.primary` == `primaryLight`). Dark mode: price now uses `primaryDark` (which P-020 lifts to AA). The discount-badge hex (`0xFFE53935`) is handled by P-006. **No new token** (§8 honored).

## P-006 — discount-pill inconsistency → RESOLVED (shared widget on the *destructive* token)

Re-verified: card badge was `Color(0xFFE53935)` (one-off red, padding h4/v1, radius 4, font 10); PDP badge was `cs.primary` (brand orange, h6/v2, radius 6, labelSmall). Same concept, two looks.

Fix: a shared `mobile/lib/design/widgets/discount_pill.dart` used by both, rendering `%<pct>` on
`cs.error`. **Why `cs.error`:** `tokens.dart:41` literally designates `destructive*` "for discount
badges," and `theme.dart:25-26` maps `colorScheme.error` → `destructive{Light,Dark}`. So the card's
red hex and the PDP's orange were *both* drift from the system's own designated discount colour. Using
it unifies them, makes them theme-aware, and adds **no new token** (the existing one was the right
target — §1.2 "use the system, not change it"). Unified style: h6/v2, `radiusSm` (6), labelSmall/w700.
*Note for design review:* `destructiveLight` (#C4400D) is brand-adjacent to `primaryLight` (#CA4E00);
if more visual pop is wanted, that's a token-value decision, out of scope here.

## P-014 — hardcoded-string sweep → **SPLIT** (scope ballooned far past this PR)

**Discovery-shift (audit undercounted, prompt misscoped).** The audit listed 11 strings (correct for
a `Text('…')`-scoped grep). A comprehensive re-grep on current `main` shows the true scope is **much
larger and cross-app**, not "card/PDP widgets" as the prompt §0 framed it:

- **11** genuine `Text('…TR…')` literals — `account/security_screen.dart` (5), `auth/email_verify_screen.dart` (2), `checkout/presentation/checkout_redirect_screen.dart` (2), `catalog/screens/product_detail_screen.dart:57` (1 — the *only* card/PDP one), `favorites/favorites_screen.dart` (1).
- **~40** hardcoded tab/page titles in `core/router/app_router.dart` via `String t(String s) => 'Mopro · $s'` (`:86`) — a title *prefixer*, **not** a localiser. Fixing these means routing through `.tr()` (or making `t()` localise), i.e. a helper refactor.
- **~4** marketing strings in `core/layout/auth_layout.dart` (`:169,211-213`).
- Plus the non-localised browser-tab label in `catalog/screens/search_screen.dart:43`.

≈ **55 genuine strings across ~10 files + a `t()` refactor + ~55×2 JSON entries (tr-TR master + en-US)
+ const-correctness handling + EN translations.** That is well beyond the §9 P-014 budget (≤200 LOC)
and the bundle ceiling, and it is a *different kind of work* (i18n infra) than card/PDP visual polish.

**Decision: split per §6/§9** ("split P-014 first — most likely to balloon"). This PR ships P-005,
P-006, P-020. P-014 → its own `feat/i18n-hardcoded-sweep` PR with its own discovery. The audit's P-014
entry is re-scoped (true count, `t()` helper) and marked SPLIT, not RESOLVED. (Only `product_detail_screen.dart:57`
is card/PDP; routing 1 of ~55 and calling P-014 "closed" would be dishonest.)

**i18n gate mechanics (recorded for the split PR):** `tr-TR.json` is the master; `make i18n-check`
(`check_i18n.sh --strict`) fails only on EXTRA keys (missing in de-DE/ar-AE is informational — partial
markets by design); `make i18n-usage` (`check_i18n_usage.dart --check`) is a dead/missing-key ratchet.
So the sweep adds keys to tr-TR + en-US and is gate-safe.

## P-020 — dark-mode AA contrast → RESOLVED (empirically verified)

`contrast_test.dart:50-55` reads `MoproTokens.primaryDark` live and marked the pair `backlog: true`
(`#E36925` on `surfaceDark` = 4.26:1 < 4.5). Fix: nudge `primaryDark` **#E36925 → #E97230** (a ~3%
lighter orange — higher luminance raises contrast on a *dark* surface). **Empirically confirmed via
`make verify-contrast`: 4.66:1** (the test recomputes from the token). Then `backlog: false` + label
updated. All other documented pairs still Pass (lightening the dark primary only *improves* the
button-fill/onPrimary pair; light-mode `primaryLight` is untouched, so `#CA4E00`-on-white stays 4.56:1).

*Direction note:* the audit's illustrative `#D45A1F` (darker) would have *lowered* contrast on the dark
surface — the correct direction is lighter. Computed/verified, not taken from the example.

## Goldens inventory (regen via CI Linux baseline — `golden-rebaseline.yml`)

Goldens are Linux-baselined with `.png.meta` sidecars (`golden_platform.dart`); 137 sidecars exist.
`make verify` does **not** run goldens (only `verify-contrast`); the golden gate is a separate CI job.
Expected shifts after these fixes:
- **P-020** — every dark-mode golden using `cs.primary` (37 `*_dark*` goldens exist): nav indicator, buttons, accents, dark card price. Subtle orange shift.
- **P-006** — card + PDP goldens showing a *discounted* product (light + dark): badge colour/padding/radius/font.
- **P-005** — dark-mode card goldens with a price (e.g. `home/goldens/recs_pdp_similar_1440_dark`).

Regen path: push commits → run `golden-rebaseline` workflow on this branch (it `flutter test
--update-goldens` on ubuntu and commits the new PNGs+sidecars) → `git pull`. **Do not regen on macOS.**

## Outcome

P-005 RESOLVED · P-006 RESOLVED · P-020 RESOLVED · **P-014 SPLIT** → `feat/i18n-hardcoded-sweep`.
This PR's title closes P-005, P-006, P-020 (not P-014 — see above). Three findings, one split.
